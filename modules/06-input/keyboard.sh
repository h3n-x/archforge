#!/usr/bin/env bash
# modules/06-input/keyboard.sh
# shellcheck shell=bash
set -euo pipefail

# shellcheck disable=SC2154,SC1091
source "${ARCHFORGE_DIR}/lib/core.sh"

module_info() {
  MODULE_NAME="Input: Keyboard layout"
  MODULE_DESC="Set console keymap and X11 keyboard layout via localectl"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES=""
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-xorg-keyboard-configuration.txt aur-wiki-linux-console-keyboard-configuration.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info
  set +T 2>/dev/null || true

  log_info "Current keyboard config:"
  localectl status 2>/dev/null || true

  local keymap=""
  if [[ "${YES_FLAG:-false}" != "true" && "${DRY_RUN:-false}" != "true" && "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    if command -v fzf &>/dev/null && [[ -t 0 ]]; then
      keymap="$(localectl list-keymaps 2>/dev/null | fzf --prompt='Console keymap: ' || true)"
    else
      read -r -p "Console keymap (e.g. us, es, de — blank to skip): " keymap
    fi
  fi

  if [[ -n "${keymap}" ]]; then
    run_cmd sudo localectl set-keymap "${keymap}"
  fi

  local x11_layout="" x11_variant=""
  if [[ "${YES_FLAG:-false}" != "true" && "${DRY_RUN:-false}" != "true" && "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    read -r -p "X11 layout (e.g. us, es, de — blank to skip): " x11_layout
    if [[ -n "${x11_layout}" ]]; then
      read -r -p "X11 variant (blank for default): " x11_variant
    fi
  fi

  if [[ -n "${x11_layout}" ]]; then
    if [[ -n "${x11_variant}" ]]; then
      run_cmd sudo localectl set-x11-keymap "${x11_layout}" "" "${x11_variant}"
    else
      run_cmd sudo localectl set-x11-keymap "${x11_layout}"
    fi
  fi

  # Wayland / Hyprland note
  # Hyprland Wiki: https://wiki.hypr.land/Configuring/Variables/#input
  log_info "Note: For Wayland compositors (Hyprland, Sway), layout is configured per-compositor."
  log_info "For Hyprland: set 'kb_layout = ${x11_layout:-us}' in ~/.config/hypr/hyprland.conf under input {}."
  log_ok "Keyboard configured."
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
