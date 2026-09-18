#!/usr/bin/env bash
# modules/10-graphics/nouveau.sh
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
  MODULE_NAME="Graphics: Nouveau (open-source NVIDIA)"
  MODULE_DESC="Configure nouveau open-source NVIDIA driver, remove proprietary driver if present"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN="NVIDIA GPU required"
  MODULE_PACKAGES="mesa"
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-nouveau.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info
  set +T 2>/dev/null || true

  # ── 1. GPU check ─────────────────────────────────────────────────────────────
  if [[ "${DETECTED_GPU:-}" != *"NVIDIA"* ]] && [[ "${DETECTED_GPU:-}" != *"nvidia"* ]]; then
    log_warn "${MODULE_HW_WARN}"
    confirm "No NVIDIA GPU detected. Continue anyway?" || return 2
  fi

  # ── 2. Nouveau vs proprietary warning ────────────────────────────────────────
  log_warn "Nouveau is the open-source NVIDIA driver."
  log_warn "Performance is significantly lower than the proprietary driver."
  log_warn "3D acceleration support varies by GPU generation."
  confirm "Proceed with Nouveau driver setup?" || return 2

  # ── 3. Check for proprietary driver ──────────────────────────────────────────
  local nvidia_installed=""
  nvidia_installed="$(pacman -Qq nvidia-utils nvidia-open 2>/dev/null | head -1 || true)"

  if [[ -n "${nvidia_installed}" ]]; then
    log_warn "Proprietary NVIDIA driver detected: ${nvidia_installed}"
    log_warn "Running both nouveau and proprietary drivers simultaneously will cause conflicts."
    confirm "Remove proprietary NVIDIA packages and switch to nouveau?" || return 2

    local to_remove=()
    for pkg in nvidia nvidia-open nvidia-utils nvidia-dkms nvidia-settings nvidia-open-dkms; do
      if pacman -Qq "${pkg}" &>/dev/null; then
        to_remove+=("${pkg}")
      fi
    done
    if [[ ${#to_remove[@]} -gt 0 ]]; then
      run_cmd sudo pacman -Rns "${to_remove[@]}"
    fi
  fi

  # ── 4. Install mesa (ArchWiki: Nouveau) ──────────────────────────────────────
  # ArchWiki: https://wiki.archlinux.org/title/Nouveau
  # For 3D acceleration, install the mesa package. The modesetting driver is
  # used by default for 2D acceleration in Xorg and native KMS in Wayland.
  pacman_install mesa

  # ── 5. Check for nouveau blacklist ───────────────────────────────────────────
  local blacklist_found=""
  blacklist_found="$(grep -rl 'blacklist nouveau' /etc/modprobe.d/ 2>/dev/null || true)"

  if [[ -n "${blacklist_found}" ]]; then
    log_warn "nouveau is blacklisted in: ${blacklist_found}"
    if confirm "Remove blacklist entry to enable nouveau?" "y"; then
      while IFS= read -r bl_file; do
        [[ -z "${bl_file}" ]] && continue
        backup_file "${bl_file}"
        local tmp_bl
        tmp_bl="$(mktemp)"
        # shellcheck disable=SC2064
        trap "rm -f '${tmp_bl}'" RETURN
        sed 's/^blacklist nouveau/# blacklist nouveau/' "${bl_file}" > "${tmp_bl}"
        run_cmd sudo cp "${tmp_bl}" "${bl_file}"
        log_ok "Removed blacklist entry from: ${bl_file}"
      done <<< "${blacklist_found}"
    else
      log_warn "nouveau will not load until blacklist is removed."
    fi
  fi

  # ── 6. KMS early load (optional) ─────────────────────────────────────────────
  if confirm "Add nouveau to mkinitcpio MODULES for early KMS (faster tty resolution)?" "y"; then
    backup_file "/etc/mkinitcpio.conf"
    local current_modules=""
    current_modules="$(grep '^MODULES=' /etc/mkinitcpio.conf 2>/dev/null || true)"

    if echo "${current_modules}" | grep -q '\bnouveau\b'; then
      log_info "nouveau is already present in mkinitcpio MODULES."
    else
      local tmp_mkini
      tmp_mkini="$(mktemp)"
      # shellcheck disable=SC2064
      trap "rm -f '${tmp_mkini}'" RETURN
      sed 's/^MODULES=(\(.*\))/MODULES=(\1 nouveau)/' /etc/mkinitcpio.conf > "${tmp_mkini}"
      run_cmd sudo cp "${tmp_mkini}" /etc/mkinitcpio.conf
    fi

    run_cmd sudo mkinitcpio -P
    log_info "initramfs regenerated with nouveau early KMS."
  fi

  # ── 7. Final summary ──────────────────────────────────────────────────────────
  log_ok "Nouveau driver configured."
  log_info "Reboot to load nouveau driver."
  log_info "Check driver status after reboot: lspci -k | grep -A3 -i nvidia"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
