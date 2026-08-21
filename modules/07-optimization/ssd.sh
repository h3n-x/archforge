#!/usr/bin/env bash
# modules/07-optimization/ssd.sh
# shellcheck shell=bash
set -euo pipefail

# shellcheck source=../../lib/core.sh
# shellcheck disable=SC2154,SC1091
source "${ARCHFORGE_DIR}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
# shellcheck disable=SC1091
source "${ARCHFORGE_DIR}/lib/packages.sh"
# shellcheck source=../../lib/backup.sh
# shellcheck disable=SC1091
source "${ARCHFORGE_DIR}/lib/backup.sh"

module_info() {
  MODULE_NAME="Optimization: SSD"
  MODULE_DESC="Enable fstrim.timer, noatime in fstab, optimal I/O scheduler, optional tmpfs /tmp"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN="SSD recommended — check your disk type before applying"
  MODULE_PACKAGES=""
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-solid-state-drive.txt aur-wiki-tmpfs.txt"
  MODULE_DEPENDS=""
}

# Parse /etc/fstab and add noatime to root mount options atomically.
# Targets column 2 ($2 == "/") — works with UUID=, LABEL=, /dev/sdX formats.
# Idempotent: no-op when noatime or relatime already present.
# Edge case: fstab uses "-" as the no-options placeholder; replaced with "noatime"
# (not ",noatime") to avoid producing invalid syntax like "-,noatime".
_add_noatime_to_fstab() {
  local file="$1"
  if awk '$2 == "/" {print $4}' "${file}" | grep -qE '(no|rel)atime'; then
    log_skip "noatime/relatime already present in fstab root entry"
    return 0
  fi
  awk '
    $2 == "/" && !/noatime/ && !/relatime/ {
      if ($4 == "-") {
        # "-" is fstab no-options placeholder; replace rather than prepend comma
        $4 = "noatime"
      } else {
        i = index($0, $4)
        $0 = substr($0, 1, i + length($4) - 1) ",noatime" substr($0, i + length($4))
      }
    }
    { print }
  ' "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
}

# Detect if the root device uses dm-crypt/LUKS.
# Source: aur-wiki-solid-state-drive.txt — dm-crypt section:
# "dm-crypt supports passing through discard requests... has security
#  implications, so it is not enabled by default."
_check_luks() {
  if lsblk -o TYPE 2>/dev/null | grep -q 'crypt'; then
    log_warn "dm-crypt/LUKS detected on this system."
    log_warn "TRIM (fstrim/discard) does NOT pass through to LUKS devices by default."
    log_warn "To enable TRIM on LUKS, follow the Arch Wiki:"
    log_warn "  https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives"
    log_warn "Note: enabling discard on LUKS has security implications (leaks block usage patterns)."
    return 1
  fi
  return 0
}

# Check actual TRIM support on the root device using lsblk --discard.
# Source: aur-wiki-solid-state-drive.txt — "To verify TRIM support, run:
#   lsblk --discard — check DISC-GRAN and DISC-MAX columns.
#   Non-zero values indicate TRIM support."
_verify_trim_support() {
  local root_source="$1"
  local disc_gran disc_max
  disc_gran="$(lsblk --discard -no DISC-GRAN "${root_source}" 2>/dev/null | head -1 | tr -d '[:space:]' || echo '0')"
  disc_max="$(lsblk  --discard -no DISC-MAX  "${root_source}" 2>/dev/null | head -1 | tr -d '[:space:]' || echo '0')"

  log_info "TRIM support check (lsblk --discard):"
  log_info "  DISC-GRAN: ${disc_gran}  DISC-MAX: ${disc_max}"

  if [[ "${disc_gran}" == "0" && "${disc_max}" == "0" ]]; then
    log_warn "DISC-GRAN and DISC-MAX are both 0 — this device may not support TRIM."
    log_warn "Enabling TRIM on a device without TRIM support can cause data loss."
    return 1
  fi
  log_ok "TRIM supported (non-zero DISC-GRAN/DISC-MAX)."
  return 0
}

module_run() {
  module_info

  local root_dev rotational root_source
  root_source="$(findmnt -no SOURCE / 2>/dev/null || true)"
  root_dev="$(lsblk -no PKNAME "${root_source}" 2>/dev/null | head -1 || echo '')"
  rotational="1"
  [[ -n "${root_dev}" ]] && rotational="$(cat "/sys/block/${root_dev}/queue/rotational" 2>/dev/null || echo '1')"

  if [[ "${rotational}" == "1" ]]; then
    log_warn "Root filesystem appears to be on a spinning disk. SSD optimizations may not apply."
    confirm "Continue anyway?" || return 2
  fi

  # Declare all temp files upfront and set a single combined trap
  local tmp tmp_rules
  tmp=""
  tmp_rules=""
  # shellcheck disable=SC2064
  trap 'rm -f "${tmp}" "${tmp_rules}" "${tmp}.tmp"' RETURN

  # ── TRIM support verification ──────────────────────────────────────────────
  # Source: aur-wiki-solid-state-drive.txt — TRIM / "To verify TRIM support"
  local trim_supported=true
  if [[ "${ARCHFORGE_TEST:-false}" != "true" && -n "${root_source}" ]]; then
    _verify_trim_support "${root_source}" || trim_supported=false
  fi

  # ── LUKS detection ────────────────────────────────────────────────────────
  # Source: aur-wiki-solid-state-drive.txt — dm-crypt section
  local luks_present=false
  if [[ "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    _check_luks || luks_present=true
  fi

  # ── TRIM strategy choice ──────────────────────────────────────────────────
  # Source: aur-wiki-solid-state-drive.txt — Periodic TRIM vs Continuous TRIM
  # Wiki recommends periodic TRIM (fstrim.timer) over continuous TRIM (discard).
  # "Ubuntu enables periodic TRIM by default; Debian does not recommend continuous
  #  TRIM; Red Hat recommends periodic TRIM over continuous TRIM if feasible."
  if [[ "${trim_supported}" == "true" ]]; then
    _configure_trim "${luks_present}"
  else
    log_warn "Skipping TRIM configuration — device may not support it."
    log_warn "Verify with: lsblk --discard"
  fi

  # ── noatime ───────────────────────────────────────────────────────────────
  log_info "noatime: skip recording read-access timestamps — reduces unnecessary writes and extends SSD lifespan."
  if confirm "Add noatime to root filesystem in /etc/fstab?" "y"; then
    backup_file "/etc/fstab"
    tmp="$(mktemp)"
    cp /etc/fstab "${tmp}"
    _add_noatime_to_fstab "${tmp}"
    echo ""
    diff /etc/fstab "${tmp}" || true
    echo ""
    if confirm "Apply fstab changes?" "y"; then
      run_cmd sudo cp "${tmp}" /etc/fstab
      log_ok "noatime added to fstab."
    fi
  fi

  # ── I/O scheduler ─────────────────────────────────────────────────────────
  if confirm "Configure I/O scheduler (mq-deadline for NVMe, bfq for SATA SSD)?" "y"; then
    local rules_file="/etc/udev/rules.d/60-archforge-ioscheduler.rules"
    backup_file "${rules_file}"
    tmp_rules="$(mktemp)"
    cat > "${tmp_rules}" <<'EOF'
# archforge — I/O scheduler optimization
# Source: Arch Wiki — Improving performance#Storage devices
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="bfq"
EOF
    run_cmd sudo cp "${tmp_rules}" "${rules_file}"
    run_cmd sudo udevadm control --reload-rules
    log_ok "I/O scheduler rules applied."
  fi

  # ── tmpfs /tmp ────────────────────────────────────────────────────────────
  # Source: aur-wiki-tmpfs.txt — Usage / Examples
  # "Mounting directories as tmpfs can be an effective way of speeding up
  #  accesses to their files." — reduces writes on SSD for temp files.
  _configure_tmpfs_tmp
}

# ── TRIM configuration ────────────────────────────────────────────────────────
_configure_trim() {
  local luks_present="$1"

  echo ""
  echo "Select TRIM strategy:"
  echo "  [1] Periodic TRIM via fstrim.timer [★ recomendado] — weekly, safe for all SSDs"
  echo "  [2] Continuous TRIM (discard mount option)         — per-operation, NVMe/SATA 3.1+ only"
  echo "  [q] Skip"
  echo ""
  # Source: aur-wiki-solid-state-drive.txt — Continuous TRIM warning:
  # "Before SATA 3.1 all TRIM commands were non-queued, so continuous trimming
  #  would produce frequent system freezes."
  log_warn "Continuous TRIM requires SATA 3.1+ or NVMe. Older SATA SSDs may freeze with 'discard'."

  local choice
  read -r -p "Choice [1]: " choice

  case "${choice:-1}" in
    1)
      if [[ "${luks_present}" == "true" ]]; then
        log_warn "fstrim.timer is enabled but will NOT trim LUKS-encrypted partitions."
        log_warn "See dm-crypt/Specialties in the Arch Wiki to enable TRIM through LUKS."
        confirm "Enable fstrim.timer anyway (will trim unencrypted partitions)?" "y" || return 0
      fi
      run_cmd sudo systemctl enable --now fstrim.timer
      log_ok "fstrim.timer enabled (weekly periodic TRIM)."
      ;;
    2)
      _configure_continuous_trim "${luks_present}"
      ;;
    q|Q)
      log_skip "TRIM configuration skipped."
      ;;
    *)
      log_warn "Invalid choice — defaulting to periodic TRIM."
      run_cmd sudo systemctl enable --now fstrim.timer
      log_ok "fstrim.timer enabled."
      ;;
  esac
}

# ── Continuous TRIM (discard mount option) ────────────────────────────────────
_configure_continuous_trim() {
  local luks_present="$1"

  # Source: aur-wiki-solid-state-drive.txt — Continuous TRIM section
  # Example from wiki: /dev/disk/by-designator/root  /  ext4  defaults,discard  0 1
  log_info "Continuous TRIM adds 'discard' to the root mount options in /etc/fstab."
  log_info "This issues TRIM commands on every file deletion instead of weekly."

  if [[ "${luks_present}" == "true" ]]; then
    log_warn "LUKS detected — 'discard' in fstab will NOT pass through LUKS without"
    log_warn "additional dm-crypt configuration (allow-discards in crypttab)."
    confirm "Add 'discard' to fstab despite LUKS being present?" || return 0
  fi

  # Detect root filesystem type to warn about XFS limitation
  # Source: aur-wiki-solid-state-drive.txt — "Specifying the discard mount
  # option in /etc/fstab does not work with an XFS / partition."
  local root_fstype
  root_fstype="$(findmnt -no FSTYPE / 2>/dev/null || echo 'unknown')"
  if [[ "${root_fstype}" == "xfs" ]]; then
    log_warn "Root filesystem is XFS — 'discard' in fstab does not work with XFS."
    log_warn "For XFS, use the kernel parameter: rootflags=discard"
    log_warn "Falling back to periodic TRIM (fstrim.timer) instead."
    run_cmd sudo systemctl enable --now fstrim.timer
    log_ok "fstrim.timer enabled (XFS requires periodic TRIM)."
    return 0
  fi

  local tmp_fstab
  tmp_fstab="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp_fstab}' '${tmp_fstab}.tmp'" RETURN

  backup_file "/etc/fstab"
  cp /etc/fstab "${tmp_fstab}"

  # Add 'discard' to root entry options (idempotent)
  if awk '$2 == "/" {print $4}' "${tmp_fstab}" | grep -q 'discard'; then
    log_skip "'discard' already present in fstab root entry."
    return 0
  fi

  awk '
    $2 == "/" && !/discard/ {
      if ($4 == "-") {
        $4 = "discard"
      } else {
        i = index($0, $4)
        $0 = substr($0, 1, i + length($4) - 1) ",discard" substr($0, i + length($4))
      }
    }
    { print }
  ' "${tmp_fstab}" > "${tmp_fstab}.tmp" && mv "${tmp_fstab}.tmp" "${tmp_fstab}"

  echo ""
  diff /etc/fstab "${tmp_fstab}" || true
  echo ""

  if confirm "Apply 'discard' to fstab?" "y"; then
    run_cmd sudo cp "${tmp_fstab}" /etc/fstab
    log_ok "'discard' added to root fstab entry (continuous TRIM enabled)."
    log_info "Changes take effect after remounting or reboot."
  fi
}

# ── tmpfs /tmp ────────────────────────────────────────────────────────────────
_configure_tmpfs_tmp() {
  # Source: aur-wiki-tmpfs.txt — Usage / Examples
  # "Under systemd, /tmp is automatically mounted as a tmpfs, if it is not
  #  already a dedicated mountpoint in /etc/fstab."
  # Adding an explicit fstab entry allows controlling size and mount options.

  # Check if /tmp is already a tmpfs
  local current_fstype
  current_fstype="$(findmnt -n -o FSTYPE /tmp 2>/dev/null || echo 'unknown')"

  if [[ "${current_fstype}" == "tmpfs" ]]; then
    # Already tmpfs (systemd default or existing fstab entry)
    if grep -qsE '^tmpfs[[:space:]]+/tmp' /etc/fstab 2>/dev/null; then
      log_skip "/tmp is already configured as tmpfs in /etc/fstab."
      return 0
    fi
    log_info "/tmp is already mounted as tmpfs (systemd default)."
    log_info "Add an fstab entry to set an explicit size limit."
  fi

  # Detect available RAM to suggest a size
  # Source: aur-wiki-tmpfs.txt: "By default, a tmpfs partition has its maximum
  #  size set to half of the available RAM."
  local total_ram_gb suggested_size
  total_ram_gb="$(free -g 2>/dev/null | awk '/^Mem:/ {print $2}' || echo 0)"
  # Use 25% of RAM, min 1G, max 4G
  if   (( total_ram_gb >= 16 )); then suggested_size="4G"
  elif (( total_ram_gb >= 8  )); then suggested_size="2G"
  elif (( total_ram_gb >= 4  )); then suggested_size="1G"
  else                                suggested_size="512M"
  fi

  log_info "System RAM: ~${total_ram_gb}GB — suggested /tmp size: ${suggested_size} (25% of RAM)."
  log_info "tmpfs /tmp reduces SSD writes for temporary files and build artifacts."
  # Source: aur-wiki-tmpfs.txt line 50:
  # tmpfs   /tmp   tmpfs   rw,nodev,nosuid,size=2G   0  0

  if confirm "Add tmpfs /tmp entry to /etc/fstab (size=${suggested_size})?" "n"; then
    local tmp_fstab
    tmp_fstab="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '${tmp_fstab}'" RETURN

    backup_file "/etc/fstab"
    cp /etc/fstab "${tmp_fstab}"
    printf '\ntmpfs\t/tmp\ttmpfs\trw,nodev,nosuid,size=%s\t0\t0\n' "${suggested_size}" >> "${tmp_fstab}"

    echo ""
    diff /etc/fstab "${tmp_fstab}" || true
    echo ""

    if confirm "Apply fstab changes?" "y"; then
      run_cmd sudo cp "${tmp_fstab}" /etc/fstab
      log_ok "tmpfs /tmp entry added (size=${suggested_size})."
      log_info "Changes take effect after reboot (or: sudo mount -a if /tmp is currently empty)."
      # Source: aur-wiki-tmpfs.txt: "if all of them are empty, it should be
      # safe to run mount -a instead of rebooting"
      log_info "Verify after reboot with: findmnt /tmp"
    fi
  fi
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
