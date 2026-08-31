#!/usr/bin/env bash
# modules/08-console/fonts.sh
# shellcheck shell=bash
set -euo pipefail

# shellcheck disable=SC2154,SC1091
source "${ARCHFORGE_DIR}/lib/core.sh"
# shellcheck disable=SC1091
source "${ARCHFORGE_DIR}/lib/backup.sh"
# shellcheck disable=SC1091
source "${ARCHFORGE_DIR}/lib/packages.sh"

module_info() {
  MODULE_NAME="Console: Fonts"
  MODULE_DESC="Install terminus console font, noto-fonts, ttf-liberation"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES="terminus-font noto-fonts noto-fonts-emoji ttf-liberation"
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-fonts.txt aur-wiki-Linux-console.txt aur-wiki-metric-compatible-fonts.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info

  pacman_install terminus-font noto-fonts noto-fonts-emoji ttf-liberation

  backup_file "/etc/vconsole.conf"

  if confirm "Set Terminus font for console (ter-v18n)?" "y"; then
    local tmp
    tmp="$(mktemp)"
    trap 'rm -f "${tmp}"' RETURN
    cp /etc/vconsole.conf "${tmp}" 2>/dev/null || true
    if grep -q '^FONT=' "${tmp}" 2>/dev/null; then
      sed -i 's/^FONT=.*/FONT=ter-v18n/' "${tmp}"
    else
      echo 'FONT=ter-v18n' >> "${tmp}"
    fi
    run_cmd sudo cp "${tmp}" /etc/vconsole.conf
  fi

  run_cmd fc-cache -f
  log_ok "Font cache updated."
  log_ok "Fonts installed."
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
