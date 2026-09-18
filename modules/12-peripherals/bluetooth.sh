#!/usr/bin/env bash
# modules/12-peripherals/bluetooth.sh
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
  MODULE_NAME="Peripherals: Bluetooth (BlueZ)"
  MODULE_DESC="Bluetooth protocol stack (BlueZ), utilities, and optional GUI manager (blueman)"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES="bluez bluez-utils"
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-bluetooth.txt"
  MODULE_DEPENDS="audio"
}

module_run() {
  module_info

  # Step 1: Install BlueZ stack and CLI utilities
  log_info "Installing BlueZ protocol stack and utilities..."
  pacman_install bluez bluez-utils

  # Step 2: Optional graphical Bluetooth manager (blueman)
  if confirm "Install blueman (GTK Bluetooth manager and system tray applet)?" "y"; then
    pacman_install blueman
  fi

  # Step 3: Enable and start system-level Bluetooth service
  log_info "Enabling system bluetooth.service..."
  run_cmd sudo systemctl enable --now bluetooth.service

  # Step 4: Check rfkill blocking status (per ArchWiki: Bluetooth#Pairing note)
  if command -v rfkill &>/dev/null; then
    local rfkill_out=""
    rfkill_out="$(rfkill list bluetooth 2>/dev/null || true)"
    if [[ -z "${rfkill_out}" ]]; then
      log_info "No Bluetooth radio currently registered in rfkill (adapter may be plugged in later)."
    elif echo "${rfkill_out}" | grep -qi "Soft blocked: yes"; then
      log_warn "Bluetooth adapter is soft-blocked by rfkill."
      run_cmd sudo rfkill unblock bluetooth
      log_ok "Bluetooth unblocked via rfkill."
    elif echo "${rfkill_out}" | grep -qi "Hard blocked: yes"; then
      log_warn "Bluetooth adapter is hard-blocked by physical airplane mode switch or laptop Fn key."
    else
      log_info "Bluetooth radio is unblocked in rfkill."
    fi
  fi

  # Step 5: Audio integration check (pipewire-audio / WirePlumber spa-bluez5)
  if pkg_installed pipewire-audio; then
    log_ok "PipeWire audio stack detected — Bluetooth audio devices (spa-bluez5) are supported."
  else
    log_info "Note: For Bluetooth audio (headsets/speakers), install the 'audio' module (pipewire-audio). Non-audio devices (keyboards, mice, gamepads) work without it."
  fi

  # Step 6: Summary instructions
  log_ok "Bluetooth stack installed and service enabled."
  log_info "To pair devices via terminal: bluetoothctl (scan on -> pair MAC -> trust MAC -> connect MAC)"
  if pkg_installed blueman; then
    log_info "To pair devices via GUI: launch blueman-manager or ensure blueman-applet is in your desktop autostart."
  fi
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
