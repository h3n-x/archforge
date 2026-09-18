#!/usr/bin/env bash
# modules/12-peripherals/audio.sh
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
  MODULE_NAME="Peripherals: Audio (PipeWire & WirePlumber)"
  MODULE_DESC="Modern audio stack with PipeWire, PulseAudio/ALSA emulation, and WirePlumber session manager"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES="pipewire pipewire-audio pipewire-pulse pipewire-alsa wireplumber"
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-pipewire.txt aur-wiki-wireplumber.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info

  # Step 1: Check for legacy PulseAudio installation
  if pkg_installed pulseaudio; then
    log_info "Legacy PulseAudio detected. Installing pipewire-pulse will replace pulseaudio packages."
  fi

  # Step 2: Install core PipeWire and WirePlumber stack
  log_info "Installing core PipeWire packages and WirePlumber session manager..."
  pacman_install pipewire pipewire-audio pipewire-pulse pipewire-alsa wireplumber

  # Step 3: Optional JACK replacement (for pro audio, DAWs, Ardour, etc.)
  if confirm "Install PipeWire JACK replacement (pipewire-jack) for pro-audio/DAW applications?" "n"; then
    pacman_install pipewire-jack
  fi

  # Step 4: Optional GUI Volume Control (pavucontrol)
  if confirm "Install pavucontrol (PulseAudio Volume Control GUI)?" "y"; then
    pacman_install pavucontrol
  fi

  # Step 5: Enable user systemd units
  log_info "Configuring systemd user services for audio..."
  enable_user_service pipewire.service pipewire-pulse.service wireplumber.service

  # Step 6: Completion message
  log_ok "PipeWire and WirePlumber audio stack installed and configured."
  log_info "Audio services run as user systemd units. Log out and back in if audio does not start immediately."
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
