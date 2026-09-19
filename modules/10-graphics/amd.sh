#!/usr/bin/env bash
# modules/10-graphics/amd.sh
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
  MODULE_NAME="Graphics: AMD GPU (AMDGPU)"
  MODULE_DESC="Install AMD open-source graphics drivers (Mesa, RADV Vulkan), optional 32-bit support, and early KMS"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN="AMD GPU required"
  MODULE_PACKAGES="mesa vulkan-radeon"
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-amd-graphics.txt"
  MODULE_DEPENDS=""
}

_check_amd_gpu() {
  local has_amd=false
  if [[ "${DETECTED_GPU:-Unknown}" == *"AMD"* ]]; then
    has_amd=true
  elif lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -qiE 'amd|radeon'; then
    has_amd=true
  fi

  if [[ "${has_amd}" != "true" ]]; then
    log_warn "${MODULE_HW_WARN}"
    confirm "No AMD GPU detected. Continue anyway?" || return 2
  fi
  return 0
}

_install_amd_packages() {
  # ArchWiki: https://wiki.archlinux.org/title/AMDGPU
  # Mesa provides the open-source DRI and Gallium drivers (radeonsi).
  # vulkan-radeon provides the RADV Vulkan implementation recommended by ArchWiki.
  pacman_install mesa vulkan-radeon

  # Optional 32-bit multilib support (e.g. Steam, Wine)
  local pacman_conf="${ARCHFORGE_PACMAN_CONF:-/etc/pacman.conf}"
  local multilib_enabled=false
  if grep -qE '^[[:space:]]*\[multilib\]' "${pacman_conf}" 2>/dev/null; then
    multilib_enabled=true
  fi

  if [[ "${multilib_enabled}" == "true" ]]; then
    if confirm "Install lib32 packages for 32-bit application support (e.g. Steam)?" "y"; then
      pacman_install lib32-mesa lib32-vulkan-radeon
    fi
  else
    log_warn "multilib repository not enabled in ${pacman_conf} -- lib32 packages unavailable."
    log_info "Enable [multilib] in /etc/pacman.conf and run 'sudo pacman -Syu' to unlock 32-bit support."
  fi
}

_configure_early_kms() {
  # ArchWiki: https://wiki.archlinux.org/title/AMDGPU#Loading
  # For early KMS start, add amdgpu to the MODULES array in /etc/mkinitcpio.conf
  local conf="${1:-${ARCHFORGE_MKINITCPIO_CONF:-/etc/mkinitcpio.conf}}"

  if ! confirm "Add amdgpu to mkinitcpio MODULES for early KMS (eliminates mode switching flicker)?" "y"; then
    log_skip "Early KMS configuration skipped."
    return 0
  fi

  if [[ ! -f "${conf}" ]]; then
    log_info "${conf} not found -- skipping mkinitcpio early KMS configuration."
    return 0
  fi

  local current_modules=""
  current_modules="$(grep '^MODULES=' "${conf}" 2>/dev/null || true)"

  if echo "${current_modules}" | grep -qE '^[[:space:]]*MODULES=\([^)]*\bamdgpu\b'; then
    log_info "amdgpu is already present in mkinitcpio MODULES."
    return 0
  fi

  backup_file "${conf}"
  local tmp_mkini
  tmp_mkini="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp_mkini}'" RETURN

  # Safely insert amdgpu into MODULES=(...) array
  sed -E 's/^[[:space:]]*MODULES=\([[:blank:]]*(.*)[[:blank:]]*\)/MODULES=(\1 amdgpu)/; s/MODULES=\([[:blank:]]+/MODULES=(/; s/[[:blank:]]+\)/)/; s/[[:blank:]]{2,}/ /g' "${conf}" > "${tmp_mkini}"
  run_cmd sudo cp "${tmp_mkini}" "${conf}"

  log_info "Regenerating initramfs with mkinitcpio -P..."
  if ! run_cmd sudo mkinitcpio -P; then
    log_error "mkinitcpio -P failed! initramfs generation was not completed."
    log_warn "Run 'sudo mkinitcpio -P' manually before rebooting to avoid unbootable systems."
    return 1
  fi
  log_ok "initramfs regenerated with amdgpu early KMS."
  return 0
}

module_run() {
  module_info
  set +T 2>/dev/null || true

  _check_amd_gpu || return $?

  log_info "Installing AMD open-source graphics drivers (Mesa & RADV)..."
  _install_amd_packages

  _configure_early_kms || return 1

  # Hybrid GPU advice (e.g. Intel iGPU + AMD dGPU or dual AMD)
  if [[ "${DETECTED_GPU:-}" == Multiple* ]] || [[ "$(lspci 2>/dev/null | grep -icE 'vga|3d|display' || true)" -gt 1 ]]; then
    log_info "Hybrid graphics detected (multiple GPUs)."
    log_info "To launch an application on the dedicated AMD GPU, use: DRI_PRIME=1 <command>"
  fi

  # Optional GPU monitoring tool
  if confirm "Install nvtop for AMD GPU utilization monitoring?" "y"; then
    pacman_install nvtop
  fi

  log_ok "AMD graphics configuration complete."
  log_info "Verify driver status after reboot: lspci -k | grep -A3 -E 'VGA|3D|Display'"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
