#!/usr/bin/env bash
# lib/packages.sh — pacman and AUR package management helpers
# shellcheck shell=bash

pkg_installed() {
  command -v pacman &>/dev/null || return 1
  pacman -Qi "$1" &>/dev/null
}

pacman_install() {
  if [[ "${ARCHFORGE_TEST:-false}" == "true" ]]; then
    echo "$*" >> "${MOCK_PKG_LOG:-/tmp/archforge-mock-pkg-$$.log}"
    return 0
  fi
  local pkg
  local -a to_install=()
  for pkg in "$@"; do
    if pkg_installed "${pkg}"; then
      log_skip "${pkg} already installed"
    else
      to_install+=("${pkg}")
    fi
  done
  if [[ ${#to_install[@]} -eq 0 ]]; then
    return 0
  fi
  run_cmd sudo pacman -S --noconfirm --needed "${to_install[@]}"
  echo "pacman: ${to_install[*]}" >> "/tmp/archforge-pkgs-$$.log"
}

aur_install() {
  if [[ -z "${AUR_HELPER:-}" ]]; then
    log_skip "No AUR helper available — skipping AUR package(s): $*"
    return 0
  fi
  if [[ "${ARCHFORGE_TEST:-false}" == "true" ]]; then
    echo "$*" >> "${MOCK_AUR_LOG:-/tmp/archforge-mock-aur-$$.log}"
    return 0
  fi
  run_cmd "${AUR_HELPER}" -S --noconfirm --needed "$@"
  echo "aur(${AUR_HELPER}): $*" >> "/tmp/archforge-pkgs-$$.log"
}

detect_aur_helper() {
  local helper
  for helper in yay paru trizen pikaur; do
    if command -v "${helper}" &>/dev/null; then
      AUR_HELPER="${helper}"
      export AUR_HELPER
      :
      return 0
    fi
  done
  AUR_HELPER=""
  export AUR_HELPER
  log_warn "No AUR helper found."
  _offer_aur_helper_install
}

_offer_aur_helper_install() {
  if [[ "${YES_FLAG:-false}" == "true" || "${DRY_RUN:-false}" == "true" ]]; then
    log_skip "Skipping AUR helper installation (non-interactive mode)"
    return 0
  fi
  echo ""
  echo "Choose an AUR helper to install:"
  echo "  [1] yay   — Go-based, most popular"
  echo "  [2] paru  — Rust-based, actively maintained (recommended)"
  echo "  [q] Skip"
  local choice
  read -r -p "Choice: " choice
  case "${choice}" in
    1) _install_aur_helper_from_source yay  "https://aur.archlinux.org/yay.git"  ;;
    2) _install_aur_helper_from_source paru "https://aur.archlinux.org/paru.git" ;;
    *) log_skip "No AUR helper installed. AUR modules will be skipped." ;;
  esac
}

_install_aur_helper_from_source() {
  local name="$1" repo="$2"
  if ! pkg_installed base-devel || ! command -v git &>/dev/null; then
    log_error "base-devel and git are required to install ${name}"
    return 1
  fi
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' RETURN
  run_cmd git clone "${repo}" "${tmp_dir}/${name}"
  ( cd "${tmp_dir}/${name}" && run_cmd makepkg -si --noconfirm ) || {
    log_error "makepkg failed — ${name} was not installed"
    return 1
  }
  AUR_HELPER="${name}"
  export AUR_HELPER
  log_ok "Installed AUR helper: ${name}"
}
