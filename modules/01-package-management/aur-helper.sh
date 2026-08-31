#!/usr/bin/env bash
# modules/01-package-management/aur-helper.sh
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
  MODULE_NAME="Package Management: AUR helper"
  MODULE_DESC="Install and configure an AUR helper (yay or paru), optimize makepkg"
  MODULE_REQUIRES_ROOT=false
  MODULE_HW_WARN=""
  MODULE_PACKAGES="base-devel git"
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-makepkg.txt aur-wiki-aur.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info

  if [[ -n "${AUR_HELPER:-}" ]]; then
    log_ok "AUR helper already available: ${AUR_HELPER}"
  else
    pacman_install base-devel git
    _offer_aur_helper_install
    if [[ -n "${AUR_HELPER:-}" ]]; then
      log_ok "AUR helper installed: ${AUR_HELPER}"
    else
      return 2
    fi
  fi

  # Security reminder — source: aur-wiki-aur.txt:
  # "Verify that the PKGBUILD and accompanying files are not malicious or
  #  untrustworthy."
  log_warn "Always review PKGBUILDs before installing AUR packages — they run arbitrary code."

  # ── makepkg optimizations ─────────────────────────────────────────────────
  # Source: aur-wiki-makepkg.txt — "Improving build times" and "Compression"
  if confirm "Optimize makepkg for faster AUR builds?" "y"; then
    _optimize_makepkg
  fi
}

# ── makepkg optimizations ─────────────────────────────────────────────────────
_optimize_makepkg() {
  local dropin_dir="/etc/makepkg.conf.d"
  local dropin="${dropin_dir}/archforge-makepkg.conf"
  local makepkg_conf="/etc/makepkg.conf"

  # Ensure drop-in directory exists (created by pacman package on modern Arch)
  if [[ ! -d "${dropin_dir}" ]]; then
    run_cmd sudo mkdir -p "${dropin_dir}"
  fi

  # ── MAKEFLAGS: parallel compilation ───────────────────────────────────────
  # Source: aur-wiki-makepkg.txt — "Parallel compilation" (lines 169-176):
  # "Users with multi-core/multi-processor systems can specify the number of
  #  jobs... MAKEFLAGS="--jobs=$(nproc)""
  local cpu_cores
  cpu_cores="$(nproc 2>/dev/null || echo 1)"
  log_info "Detected ${cpu_cores} CPU thread(s) — MAKEFLAGS will use --jobs=${cpu_cores}."

  # ── BUILDDIR: build in tmpfs ──────────────────────────────────────────────
  # Source: aur-wiki-makepkg.txt — "Building from files in memory" (lines 178-191):
  # "moving the working directory to a tmpfs may bring improvements in build times"
  # Wiki warns: "Avoid compiling larger packages in tmpfs to prevent running out of memory."
  # Wiki warns: "packages compiled in tmpfs will not persist across reboot."
  local tmp_space_gb df_out
  df_out="$(df -BG /tmp 2>/dev/null || true)"
  tmp_space_gb="$(echo "${df_out}" | awk 'NR==2{gsub("G",""); print $4+0}')"
  [[ -z "${tmp_space_gb}" ]] && tmp_space_gb=0
  local use_tmpfs=false
  if (( tmp_space_gb >= 4 )); then
    log_info "Available space in /tmp: ~${tmp_space_gb}GB — sufficient for BUILDDIR."
    log_info "BUILDDIR=/tmp/makepkg: builds in RAM, faster I/O, but lost on reboot."
    use_tmpfs=true
  else
    log_warn "Available space in /tmp: ~${tmp_space_gb}GB — less than 4GB recommended."
    log_warn "BUILDDIR in tmpfs skipped to avoid running out of memory during large builds."
  fi

  # ── Write drop-in file ────────────────────────────────────────────────────
  if [[ -f "${dropin}" ]]; then
    log_skip "${dropin} already exists — not overwriting."
  else
    backup_file "${dropin}"
    local tmp
    tmp="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '${tmp}'" RETURN

    {
      printf '# archforge makepkg optimizations\n'
      printf '# Source: aur-wiki-makepkg.txt (Arch Wiki makepkg article)\n\n'

      # Parallel compilation
      printf '# Parallel compilation — use all available CPU threads\n'
      printf '# Source: aur-wiki-makepkg.txt — "Parallel compilation"\n'
      printf 'MAKEFLAGS="--jobs=%s"\n\n' "${cpu_cores}"

      # BUILDDIR in tmpfs (only if sufficient space)
      if [[ "${use_tmpfs}" == "true" ]]; then
        printf '# Build directory in tmpfs — faster I/O at the cost of RAM\n'
        printf '# Source: aur-wiki-makepkg.txt — "Building from files in memory"\n'
        printf '# Note: packages built in /tmp are lost on reboot (only affects caching)\n'
        printf 'BUILDDIR=/tmp/makepkg\n\n'
      fi

      # Parallel zstd compression
      # Source: aur-wiki-makepkg.txt — "Utilizing multiple cores on compression" (lines 241-245):
      # "zstd supports symmetric multiprocessing... --auto-threads=logical"
      printf '# Parallel zstd compression using all logical CPU cores\n'
      printf '# Source: aur-wiki-makepkg.txt — "Utilizing multiple cores on compression"\n'
      printf 'COMPRESSZST=(zstd -c -T0 --auto-threads=logical -)\n'
    } > "${tmp}"

    run_cmd sudo cp "${tmp}" "${dropin}"
    log_ok "makepkg drop-in written to ${dropin}."
  fi

  # ── Disable debug packages and LTO ───────────────────────────────────────
  # Source: aur-wiki-makepkg.txt — "Disable debug packages and LTO" (lines 220-226):
  # "Building debug packages... slows down the build process."
  # "Link-time optimization produces more optimized binaries but greatly
  #  lengthens the build process."
  if [[ -f "${makepkg_conf}" ]]; then
    local has_debug has_lto
    has_debug="$(grep -c '\bdebug\b' "${makepkg_conf}" 2>/dev/null || echo 0)"
    has_lto="$(grep -c '\blto\b' "${makepkg_conf}" 2>/dev/null || echo 0)"

    if (( has_debug > 0 || has_lto > 0 )); then
      log_info "Disabling debug packages (!debug) and LTO (!lto) speeds up AUR builds significantly."
      log_info "These options are enabled by default since pacman 6.0.2-9 (February 2024)."
      if confirm "Disable debug packages and LTO in /etc/makepkg.conf?" "y"; then
        backup_file "${makepkg_conf}"
        # Add !debug and !lto if not already present — sed only modifies OPTIONS array
        run_cmd sudo sed -i \
          's/OPTIONS=(\(.*\)\bdebug\b/OPTIONS=(\1!debug/g;
           s/OPTIONS=(\(.*\)\blto\b/OPTIONS=(\1!lto/g' \
          "${makepkg_conf}"
        log_ok "!debug and !lto set in OPTIONS."
      fi
    fi
  fi

  # ── ccache ────────────────────────────────────────────────────────────────
  # Source: aur-wiki-makepkg.txt — "Using a compilation cache" (line 195):
  # "The use of ccache can improve build times by caching the results of
  #  compilations for successive use."
  if confirm "Install ccache (speeds up recompilation of unchanged AUR packages)?" "y"; then
    pacman_install ccache

    if [[ -f "${makepkg_conf}" ]]; then
      # Enable ccache in BUILDENV array: change !ccache → ccache
      if grep -q '!ccache' "${makepkg_conf}" 2>/dev/null; then
        backup_file "${makepkg_conf}"
        run_cmd sudo sed -i 's/!ccache/ccache/g' "${makepkg_conf}"
        log_ok "ccache enabled in /etc/makepkg.conf BUILDENV."
      elif ! grep -q '\bccache\b' "${makepkg_conf}" 2>/dev/null; then
        log_warn "Could not find '!ccache' in /etc/makepkg.conf — enable ccache manually."
        log_warn "In /etc/makepkg.conf, add 'ccache' to the BUILDENV array."
      else
        log_skip "ccache already enabled in /etc/makepkg.conf."
      fi
    fi

    log_info "ccache stores compilation results in ~/.cache/ccache by default."
    log_info "View cache stats with: ccache -s"
  fi

  log_ok "makepkg optimizations applied."
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
