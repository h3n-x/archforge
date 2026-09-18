#!/usr/bin/env bash
# modules/04-power/tlp.sh
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
  MODULE_NAME="Power: TLP"
  MODULE_DESC="Battery optimization for laptops via TLP, ThinkPad battery thresholds, USB denylist"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN="Designed for laptops — not recommended on desktop"
  MODULE_PACKAGES="tlp"
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-tlp.txt aur-wiki-laptop.txt"
  MODULE_DEPENDS=""
}

module_run() {
  set +T 2>/dev/null || true
  module_info

  if [[ "${SYSTEM_TYPE:-desktop}" == "desktop" ]]; then
    log_warn "${MODULE_HW_WARN}"
    confirm "Apply TLP on desktop anyway?" || return 2
  fi

  # ── Install TLP ────────────────────────────────────────────────────────────
  pacman_install tlp

  # ── Conflict check: power-profiles-daemon ─────────────────────────────────
  # Source: https://wiki.archlinux.org/title/CPU_frequency_scaling#power-profiles-daemon
  # "power-profiles-daemon conflicts with other power management services such as TLP... disable by masking it."
  if systemctl is-active --quiet power-profiles-daemon.service 2>/dev/null || systemctl is-enabled --quiet power-profiles-daemon.service 2>/dev/null; then
    log_warn "power-profiles-daemon conflicts with TLP."
    if confirm "Mask conflicting power-profiles-daemon.service?" "y"; then
      run_cmd sudo systemctl mask --now power-profiles-daemon.service
      log_ok "power-profiles-daemon masked."
    fi
  fi

  # Source: aur-wiki-tlp.txt — Radio Device Wizard:
  # "When using tlp-rdw it is required to use NetworkManager and enabling
  #  NetworkManager-dispatcher.service."
  if confirm "Install tlp-rdw (radio device wizard for WiFi/BT on lid open)?"; then
    pacman_install tlp-rdw
    run_cmd sudo systemctl enable NetworkManager-dispatcher.service
  fi

  # ── Base configuration ─────────────────────────────────────────────────────
  backup_file "/etc/tlp.conf"
  run_cmd sudo cp "${ARCHFORGE_DIR}/configs/tlp.conf" /etc/tlp.conf

  # ── CPU governor conflict detection ───────────────────────────────────────
  # Source: aur-wiki-tlp.txt — Configuration section.
  # TLP manages CPU scaling governors via CPU_SCALING_GOVERNOR_ON_AC/BAT.
  # The performance.sh module writes udev rules for the same.
  # Both active simultaneously causes unpredictable governor switching.
  _check_cpufreq_conflict

  # ── ThinkPad battery charge thresholds ────────────────────────────────────
  # Source: aur-wiki-tlp.txt — "ThinkPads only" section:
  # "Controlling the charge thresholds... is possible using threshy."
  # TLP supports START/STOP_CHARGE_THRESH_BATn parameters for ThinkPads.
  # Parameter names from TLP Settings documentation referenced by the wiki.
  _configure_battery_thresholds

  # ── USB autosuspend denylist ───────────────────────────────────────────────
  # Source: aur-wiki-tlp.txt — USB autosuspend section:
  # "blacklist specific devices from being auto-suspended"
  # USB_DENYLIST="ID1 ID2" — get IDs from lsusb
  _configure_usb_denylist

  # ── Enable TLP service ─────────────────────────────────────────────────────
  # Source: aur-wiki-tlp.txt — Installation section:
  # "Enable/start tlp.service. One should also mask systemd-rfkill.service
  #  and socket systemd-rfkill.socket to avoid conflicts."
  run_cmd sudo systemctl enable --now tlp.service
  run_cmd sudo systemctl mask systemd-rfkill.service
  run_cmd sudo systemctl mask systemd-rfkill.socket
  log_ok "TLP configured."
  log_info "Apply changes after editing config: sudo tlp start"
  log_info "Check TLP status with: tlp-stat -s"
}

# ── CPU governor conflict detection ──────────────────────────────────────────
_check_cpufreq_conflict() {
  local cpufreq_rules="/etc/udev/rules.d/50-archforge-cpufreq.rules"

  # Check if TLP is managing CPU governors in the base config
  if grep -qsE '^CPU_SCALING_GOVERNOR' /etc/tlp.conf 2>/dev/null; then
    if [[ -f "${cpufreq_rules}" ]]; then
      log_warn "TLP manages CPU governors (CPU_SCALING_GOVERNOR_ON_AC/BAT in /etc/tlp.conf)"
      log_warn "AND udev cpufreq rules from the performance module exist: ${cpufreq_rules}"
      log_warn "Both active simultaneously causes unpredictable governor switching."
      log_warn "Recommended: remove ${cpufreq_rules} and let TLP manage governors."
      if confirm "Remove conflicting udev cpufreq rules (let TLP manage CPU governors)?" "y"; then
        backup_file "${cpufreq_rules}"
        run_cmd sudo rm -f "${cpufreq_rules}"
        run_cmd sudo udevadm control --reload-rules
        log_ok "Removed udev cpufreq rules — TLP will now manage CPU governors."
      fi
    fi
  fi
}

# ── ThinkPad battery charge thresholds ───────────────────────────────────────
_configure_battery_thresholds() {
  # Source: aur-wiki-tlp.txt — "ThinkPads only" section.
  # Charge thresholds are hardware-level battery management supported on
  # ThinkPads and select Lenovo models. TLP exposes them via:
  # START_CHARGE_THRESH_BAT0 / STOP_CHARGE_THRESH_BAT0

  # Detect ThinkPad/Lenovo via DMI without requiring dmidecode
  local sys_vendor=""
  sys_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  local product_name=""
  product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"

  local is_thinkpad=false
  if echo "${sys_vendor}${product_name}" | grep -qi 'lenovo\|thinkpad'; then
    is_thinkpad=true
  fi

  if [[ "${is_thinkpad}" == "false" ]]; then
    log_info "Battery charge thresholds are only supported on ThinkPad and select Lenovo models."
    log_info "Detected vendor: '${sys_vendor}' — skipping threshold configuration."
    return 0
  fi

  log_info "ThinkPad/Lenovo detected: ${product_name} (${sys_vendor})"
  log_info "Battery charge thresholds extend battery lifespan by limiting charge range."
  log_info "Charging between 40-80% is recommended for maximum longevity."
  log_info "This reduces max available capacity in exchange for longer battery life."

  if ! confirm "Configure battery charge thresholds?" "y"; then
    return 0
  fi

  # Interactive threshold input with validation
  local start_thresh=40 stop_thresh=80
  if [[ "${YES_FLAG:-false}" != "true" ]] && [[ "${DRY_RUN:-false}" != "true" ]] && [[ "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    while true; do
      read -r -p "START charge threshold (% — charge starts above this, recommended 40): " start_thresh || true
      start_thresh="${start_thresh:-40}"
      if [[ "${start_thresh}" =~ ^[0-9]+$ ]] && (( start_thresh >= 0 && start_thresh <= 99 )); then
        break
      fi
      log_warn "Invalid value '${start_thresh}' — must be 0-99."
    done

    while true; do
      read -r -p "STOP charge threshold  (% — charge stops here, recommended 80): " stop_thresh || true
      stop_thresh="${stop_thresh:-80}"
      if [[ "${stop_thresh}" =~ ^[0-9]+$ ]] && (( stop_thresh > start_thresh && stop_thresh <= 100 )); then
        break
      fi
      log_warn "Invalid value '${stop_thresh}' — must be ${start_thresh}–100 and greater than START."
    done
  fi

  log_info "Thresholds: START=${start_thresh}%  STOP=${stop_thresh}%"
  log_info "Battery will charge from ${start_thresh}% up to ${stop_thresh}% only."

  # Write to /etc/tlp.d/ drop-in — cleaner than modifying tlp.conf directly.
  # Source: aur-wiki-tlp.txt — "you can also place files in /etc/tlp.d/"
  local dropin="/etc/tlp.d/10-archforge-thinkpad.conf"
  backup_file "${dropin}"
  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp}'" RETURN
  cat > "${tmp}" <<EOF
# ThinkPad battery charge thresholds
# Source: aur-wiki-tlp.txt — "ThinkPads only" section
# Managed by archforge — edit or remove to change threshold settings.

START_CHARGE_THRESH_BAT0=${start_thresh}
STOP_CHARGE_THRESH_BAT0=${stop_thresh}

# BAT1 (second battery in some ThinkPads with UltraBay/slice battery)
START_CHARGE_THRESH_BAT1=${start_thresh}
STOP_CHARGE_THRESH_BAT1=${stop_thresh}
EOF
  run_cmd sudo cp "${tmp}" "${dropin}"
  log_ok "Battery thresholds written to ${dropin}."
  log_info "Check threshold status after TLP starts: tlp-stat -b"
}

# ── USB autosuspend denylist ──────────────────────────────────────────────────
_configure_usb_denylist() {
  # Source: aur-wiki-tlp.txt — USB autosuspend section:
  # "When starting TLP with the default configuration, some USB devices such as
  #  audio DACs will be powered down when running on battery."
  # "blacklist specific devices from being auto-suspended"
  # Example from wiki troubleshooting: USB_DENYLIST="8087:0aaa"
  # "Get the device ID for your bluetooth device from lsusb -v"

  if ! confirm "Configure USB autosuspend denylist (prevent specific devices from being suspended)?" "n"; then
    return 0
  fi

  # Show connected USB devices — regular lsusb is cleaner than lsusb -v
  # Format: Bus XXX Device XXX: ID XXXX:XXXX Manufacturer Description
  log_info "Connected USB devices (ID format: XXXX:XXXX — use this as the denylist entry):"
  echo ""
  lsusb 2>/dev/null | awk '{print "  " $6 "\t" substr($0, index($0,$7))}' || lsusb 2>/dev/null || true
  echo ""

  log_info "Enter USB device IDs to exclude from autosuspend."
  log_info "Example: 8087:0aaa for Intel Bluetooth (space-separated for multiple)."
  local denylist_ids=""
  if [[ "${YES_FLAG:-false}" != "true" ]] && [[ "${DRY_RUN:-false}" != "true" ]] && [[ "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    read -r -p "USB denylist IDs (blank to skip): " denylist_ids || true
  fi

  if [[ -z "${denylist_ids}" ]]; then
    log_skip "No USB IDs entered — skipping denylist configuration."
    return 0
  fi

  # Write to /etc/tlp.d/ drop-in
  local dropin="/etc/tlp.d/20-archforge-usb.conf"
  backup_file "${dropin}"
  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp}'" RETURN
  cat > "${tmp}" <<EOF
# USB autosuspend denylist
# Source: aur-wiki-tlp.txt — USB autosuspend section
# Devices listed here will never be suspended by TLP.

USB_DENYLIST="${denylist_ids}"
EOF
  run_cmd sudo cp "${tmp}" "${dropin}"
  log_ok "USB denylist written to ${dropin}."
  log_info "Restart TLP to apply: sudo tlp start"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
