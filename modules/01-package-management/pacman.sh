#!/usr/bin/env bash
# modules/01-package-management/pacman.sh
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
  MODULE_NAME="Package Management: pacman"
  MODULE_DESC="Parallel downloads, color output, ILoveCandy, optimized mirrors, keyring, pkgfile, cache cleanup"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES="pacman-contrib reflector pkgfile archlinux-keyring"
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-pacman.txt aur-wiki-pacman-tips-and-tricks.txt aur-wiki-mirrors.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info

  local pkgs_log="/tmp/archforge-pkgs-$$.log"
  if [[ -s "${pkgs_log}" ]]; then
    log_warn "Packages have already been installed this session."
    log_warn "For optimal mirror and package configuration, run the pacman module first."
  fi

  local pacman_conf="${PACMAN_CONF:-/etc/pacman.conf}"

  if [[ ! -f "${pacman_conf}" ]]; then
    log_warn "pacman: ${pacman_conf} not found — skipping"
    return 2
  fi

  # ── pacman.conf options ───────────────────────────────────────────────────
  backup_file "${pacman_conf}"

  log_info "Enabling parallel downloads, color, and ILoveCandy in ${pacman_conf}"

  local tmp
  tmp="$(mktemp)"
  cp "${pacman_conf}" "${tmp}"

  _set_pacman_option "${tmp}" "ParallelDownloads" "5"
  _set_pacman_option "${tmp}" "Color"              ""
  _set_pacman_option "${tmp}" "ILoveCandy"         ""
  _set_pacman_option "${tmp}" "VerbosePkgLists"    ""

  diff "${pacman_conf}" "${tmp}" || true
  if ! confirm "Apply these changes to ${pacman_conf}?" "y"; then
    rm -f "${tmp}"
    return 2
  fi
  run_cmd sudo cp "${tmp}" "${pacman_conf}"
  rm -f "${tmp}"

  if confirm "Enable [multilib] repository?" "y"; then
    backup_file "${pacman_conf}"
    local tmp2
    tmp2="$(mktemp)"
    cp "${pacman_conf}" "${tmp2}"
    sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' "${tmp2}"
    run_cmd sudo cp "${tmp2}" "${pacman_conf}"
    rm -f "${tmp2}"
    run_cmd sudo pacman -Sy
  fi

  pacman_install reflector pacman-contrib

  # ── Reflector mirror timer ────────────────────────────────────────────────
  _configure_reflector

  # ── Keyring ───────────────────────────────────────────────────────────────
  _configure_keyring

  # ── pkgfile ───────────────────────────────────────────────────────────────
  _configure_pkgfile

  # ── Cache cleanup timer ───────────────────────────────────────────────────
  _configure_paccache

  log_ok "pacman configured."
}

# ── Reflector mirror timer ────────────────────────────────────────────────────
_configure_reflector() {
  # Source: aur-wiki-mirrors.txt — "Client-side ranking":
  # "Reflector — Retrieves the latest mirrorlist from the MirrorStatus page,
  #  filters and sorts them by speed and overwrites /etc/pacman.d/mirrorlist.
  #  Provides automation with a systemd service and timer."
  local reflector_conf="/etc/xdg/reflector/reflector.conf"

  log_info "Reflector updates /etc/pacman.d/mirrorlist automatically via a systemd timer."
  log_info "Enter comma-separated country names for mirror selection."
  log_info "Examples: France,Germany  /  United States  /  Spain,Portugal"

  local countries
  read -r -p "Countries [France,Germany,Spain]: " countries || countries="France,Germany,Spain"
  countries="${countries:-France,Germany,Spain}"

  backup_file "${reflector_conf}"
  local tmp_ref
  tmp_ref="$(mktemp)"
  cat > "${tmp_ref}" <<EOF
# reflector configuration
# Source: aur-wiki-mirrors.txt — Reflector (client-side mirror ranking)
--save /etc/pacman.d/mirrorlist
--protocol https
--country ${countries}
--latest 10
--sort rate
EOF
  run_cmd sudo cp "${tmp_ref}" "${reflector_conf}"
  rm -f "${tmp_ref}"

  # Enable timer for automatic weekly mirror refresh
  run_cmd sudo systemctl enable --now reflector.timer
  log_ok "reflector.timer enabled — mirrorlist refreshed weekly."
  log_info "Run manually any time: sudo reflector --save /etc/pacman.d/mirrorlist --protocol https --country '${countries}' --latest 10 --sort rate"
}

# ── Keyring ───────────────────────────────────────────────────────────────────
_configure_keyring() {
  # Source: aur-wiki-pacman.txt — "Package security":
  # "pacman supports package signatures... SigLevel = Required DatabaseOptional,
  #  enables signature verification for all packages."
  # Source: aur-wiki-pacman.txt — Troubleshooting:
  # "That same error may also appear if archlinux-keyring is out-of-date,
  #  preventing pacman from verifying signatures."

  log_info "Ensuring archlinux-keyring is up to date to prevent signature verification errors."
  pacman_install archlinux-keyring

  # Populate keyring with keys from archlinux-keyring package
  if [[ "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    run_cmd sudo pacman-key --populate archlinux
    log_ok "Keyring populated (pacman-key --populate archlinux)."
  fi

  # Optional: refresh keys from keyserver (slow — requires network to keyserver)
  log_info "Refreshing keys contacts a keyserver and can take several minutes."
  if confirm "Refresh all pacman keys from keyserver (optional, slow)?" "n"; then
    if [[ "${ARCHFORGE_TEST:-false}" != "true" ]]; then
      run_cmd sudo pacman-key --refresh-keys
      log_ok "Keyring refreshed from keyserver."
    fi
  fi
}

# ── pkgfile ───────────────────────────────────────────────────────────────────
_configure_pkgfile() {
  # Source: aur-wiki-pacman.txt — line 249:
  # "For advanced functionality, install pkgfile, which uses a separate database
  #  with all files and their associated packages."
  # Source: aur-wiki-pacman-tips-and-tricks.txt — "Utilities":
  # "pkgfile — Tool that finds what package owns a file."
  # Source: aur-wiki-pacman.txt — "Tip":
  # "You can enable/start the pacman-filesdb-refresh.timer (provided within the
  #  pacman-contrib package) to refresh pacman files database weekly."

  log_info "pkgfile searches the database to find which package owns a given file."
  log_info "Example: pkgfile missing_command — find which package provides a command."

  if ! confirm "Install pkgfile (file-to-package lookup tool)?" "y"; then
    return 0
  fi

  pacman_install pkgfile

  # Initial database population
  if [[ "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    run_cmd sudo pkgfile --update
    log_ok "pkgfile database populated."
  fi

  # Enable automatic weekly database updates
  # The pkgfile-update.timer is provided by the pkgfile package
  run_cmd sudo systemctl enable --now pkgfile-update.timer
  log_ok "pkgfile-update.timer enabled — pkgfile database refreshed weekly."
  log_info "Usage: pkgfile <filename>   — find which package owns a file"
  log_info "Usage: pkgfile -s <name>    — search by partial name"

  # Also enable pacman's own files database refresh timer (from pacman-contrib)
  # Source: aur-wiki-pacman.txt — "Tip" (line 187):
  # "enable/start the pacman-filesdb-refresh.timer (provided within the pacman-contrib
  #  package) to refresh pacman files database weekly."
  if systemctl list-unit-files pacman-filesdb-refresh.timer &>/dev/null 2>&1; then
    run_cmd sudo systemctl enable --now pacman-filesdb-refresh.timer
    log_ok "pacman-filesdb-refresh.timer enabled — pacman -F database refreshed weekly."
  fi
}

# ── Cache cleanup timer ───────────────────────────────────────────────────────
_configure_paccache() {
  # Source: aur-wiki-pacman.txt — "Cleaning the package cache":
  # "Enable and start paccache.timer to discard unused packages weekly."
  # "paccache -r: deletes all cached versions of installed and uninstalled packages,
  #  except for the most recent three, by default"

  if systemctl is-enabled --quiet paccache.timer 2>/dev/null; then
    log_skip "paccache.timer already enabled."
    return 0
  fi

  log_info "paccache.timer automatically removes old cached packages weekly."
  log_info "Default: keeps the 3 most recent versions of each package."

  if confirm "Enable paccache.timer (weekly package cache cleanup)?" "y"; then
    run_cmd sudo systemctl enable --now paccache.timer
    log_ok "paccache.timer enabled — package cache cleaned weekly."
    log_info "Run manually: paccache -r (keep 3 versions) / paccache -rk1 (keep 1 version)"
  fi
}

_set_pacman_option() {
  local file="$1" key="$2" value="$3"
  # Escape key for use as sed pattern (BRE safe)
  local ek ev
  ek="$(printf '%s' "${key}"   | sed 's/[]\/$*.^[]/\\&/g')"
  ev="$(printf '%s' "${value}" | sed 's/[\/&]/\\&/g')"

  if grep -q "^#${ek}" "${file}"; then
    if [[ -n "${value}" ]]; then
      sed -i "s/^#${ek}.*/${ek} = ${ev}/" "${file}"
    else
      sed -i "s/^#${ek}.*/${ek}/" "${file}"
    fi
  elif ! grep -q "^${ek}" "${file}"; then
    if [[ -n "${value}" ]]; then
      sed -i "/^\[options\]/a ${ek} = ${ev}" "${file}"
    else
      sed -i "/^\[options\]/a ${ek}" "${file}"
    fi
  fi
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
