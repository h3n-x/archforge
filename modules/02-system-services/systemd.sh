#!/usr/bin/env bash
# modules/02-system-services/systemd.sh
# shellcheck shell=bash
set -euo pipefail

# shellcheck source=../../lib/core.sh
# shellcheck disable=SC2154,SC1091
source "${ARCHFORGE_DIR}/lib/core.sh"
# shellcheck source=../../lib/backup.sh
# shellcheck disable=SC1091
source "${ARCHFORGE_DIR}/lib/backup.sh"

module_info() {
  MODULE_NAME="System Services: systemd"
  MODULE_DESC="Journal size limit + persistent storage, faster shutdown, timesyncd, failed units report, boot analysis"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES=""
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-systemd.txt aur-wiki-systemd-journal.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info

  # ── Journal: persistent storage + size limit ──────────────────────────────
  _configure_journal

  # ── Faster shutdown ───────────────────────────────────────────────────────
  local changed=false
  backup_file "/etc/systemd/system.conf"
  log_info "Setting DefaultTimeoutStopSec=10s"
  if confirm "Set DefaultTimeoutStopSec=10s in system.conf?" "y"; then
    if grep -q 'DefaultTimeoutStopSec' /etc/systemd/system.conf 2>/dev/null; then
      run_cmd sudo sed -i \
        's/^#*DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=10s/' \
        /etc/systemd/system.conf
    else
      run_cmd sudo bash -c \
        'set -euo pipefail; echo "DefaultTimeoutStopSec=10s" >> /etc/systemd/system.conf'
    fi
    changed=true
  fi

  # ── NTP ───────────────────────────────────────────────────────────────────
  local timesyncd_active=false
  if [[ "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
      timesyncd_active=true
    fi
  fi
  if [[ "${timesyncd_active}" == "false" ]]; then
    if confirm "Enable systemd-timesyncd (NTP)?" "y"; then
      run_cmd sudo systemctl enable --now systemd-timesyncd
      changed=true
    fi
  else
    log_ok "systemd-timesyncd is already active."
  fi

  # ── Failed units report ───────────────────────────────────────────────────
  local failed=""
  if [[ "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    failed="$(systemctl --failed --no-legend 2>/dev/null | awk 'NF && $1 != "●" {print $1}' || true)"
  fi
  if [[ -n "${failed}" ]]; then
    log_warn "Failed systemd units detected:"
    echo "${failed}"
  else
    log_ok "No failed systemd units."
  fi

  # ── Reload only if changes were applied ──────────────────────────────────
  if [[ "${changed}" == "true" ]]; then
    run_cmd sudo systemctl daemon-reload
  fi

  # ── Boot analysis ─────────────────────────────────────────────────────────
  _boot_analysis

  log_ok "systemd configured."
}

# ── Journal: persistent storage + size limit ──────────────────────────────────
_configure_journal() {
  # Source: aur-wiki-systemd-journal.txt — "Journal storage":
  # "Since the default mode for the journal is Storage=persistent, the journal
  #  will write to /var/log/journal/... If the mode is manually configured to
  #  Storage=auto, systemd will instead write its logs to /run/log/journal/
  #  in a non-persistent way."
  # Source: aur-wiki-systemd-journal.txt — "Journal size limit" (drop-in approach):
  # "It is also possible to use the drop-in snippets configuration override mechanism
  #  rather than editing the global configuration file."
  # "/etc/systemd/journald.conf.d/00-journal-size.conf"
  # Source: aur-wiki-systemd.txt — "Boot time increasing over time":
  # "The problem for some users has been due to /var/log/journal becoming too large.
  #  The solution is... setting a journal file size limit."

  local dropin_dir="/etc/systemd/journald.conf.d"
  local dropin="${dropin_dir}/archforge.conf"

  if [[ -f "${dropin}" ]]; then
    log_skip "${dropin} already exists."
    return 0
  fi

  log_info "Journal storage: 'persistent' writes to /var/log/journal/ (survives reboots)."
  log_info "Without a size limit the journal can grow to 10% of the filesystem (up to 4 GiB)."

  local max_use
  read -r -p "Maximum journal size [500M]: " max_use || max_use="500M"
  max_use="${max_use:-500M}"

  # Validate: accept values like 100M, 2G, 500M
  if [[ ! "${max_use}" =~ ^[0-9]+(M|G|K|T)$ ]]; then
    log_warn "Invalid value '${max_use}' — using 500M."
    max_use="500M"
  fi

  backup_file "${dropin}"
  local tmp
  tmp="$(mktemp)"

  run_cmd sudo mkdir -p "${dropin_dir}"
  cat > "${tmp}" <<EOF
# archforge journal configuration
# Source: aur-wiki-systemd-journal.txt — "Journal storage" and "Journal size limit"

[Journal]
# Storage=persistent: write to /var/log/journal/ (survives reboots).
# Default in Arch Linux, explicitly set here to prevent accidental override.
Storage=persistent

# Limit persistent journal size (default: 10% of filesystem, max 4 GiB).
# Source: aur-wiki-systemd-journal.txt — "Journal size limit"
SystemMaxUse=${max_use}
EOF
  run_cmd sudo cp "${tmp}" "${dropin}"
  rm -f "${tmp}"
  # Source: aur-wiki-systemd-journal.txt line 184:
  # "Restart the systemd-journald.service after changing this setting to apply the new limit."
  run_cmd sudo systemctl restart systemd-journald.service
  log_ok "Journal: Storage=persistent, SystemMaxUse=${max_use} (${dropin})."
  log_info "Check current journal disk usage with: journalctl --disk-usage"
}

# ── Boot analysis ─────────────────────────────────────────────────────────────
_boot_analysis() {
  # Source: aur-wiki-systemd.txt — systemd components:
  # "systemd-analyze(1) — may be used to determine boot-up performance, statistics
  #  and retrieve other state and tracing information."
  # Source: aur-wiki-systemd.txt — "Boot time increasing over time":
  # "After using systemd-analyze blame NetworkManager is being reported as taking
  #  an unusually large amount of time to start."

  if [[ "${ARCHFORGE_TEST:-false}" == "true" ]]; then
    return 0
  fi

  echo ""
  log_info "Boot performance analysis via systemd-analyze:"

  local boot_time
  boot_time="$(systemd-analyze 2>/dev/null || true)"
  if [[ -n "${boot_time}" ]]; then
    echo "${boot_time}"
  fi

  echo ""
  if confirm "Show per-service boot times (systemd-analyze blame)?" "y"; then
    # Source: aur-wiki-systemd.txt — "systemd-analyze blame"
    systemd-analyze blame 2>/dev/null | head -20 || true
  fi

  if confirm "Show critical boot chain (systemd-analyze critical-chain)?" "n"; then
    systemd-analyze critical-chain 2>/dev/null || true
  fi
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
