#!/usr/bin/env bash
# modules/10-graphics/intel.sh
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
  MODULE_NAME="Graphics: Intel Graphics"
  MODULE_DESC="Install Intel open-source graphics drivers (Mesa, ANV Vulkan, VA-API) and optional 32-bit support"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN="Intel GPU required"
  MODULE_PACKAGES="mesa vulkan-intel intel-media-driver"
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-intel-graphics.txt"
  MODULE_DEPENDS=""
}

_check_intel_gpu() {
  local has_intel=false
  if [[ "${DETECTED_GPU:-Unknown}" == *"Intel"* ]]; then
    has_intel=true
  elif lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -qi 'intel'; then
    has_intel=true
  fi

  if [[ "${has_intel}" != "true" ]]; then
    log_warn "${MODULE_HW_WARN}"
    confirm "No Intel GPU detected. Continue anyway?" || return 2
  fi
  return 0
}

_select_vaapi_driver() {
  if [[ "${YES_FLAG:-false}" == "true" || "${DRY_RUN:-false}" == "true" || "${ARCHFORGE_TEST:-false}" == "true" ]]; then
    echo "intel-media-driver"
    return 0
  fi

  echo "" >&2
  echo "Select VA-API driver for hardware video acceleration:" >&2
  echo "  [1] intel-media-driver [* recommended] -- Broadwell (Gen 8, 2014+) through modern Core / Arc GPUs (iHD)" >&2
  echo "  [2] libva-intel-driver (legacy)        -- Haswell (Gen 7.5, 2013) and older hardware (i965)" >&2
  echo "  [s] Skip VA-API installation" >&2

  local choice="1"
  read -r -p "Driver [1]: " choice
  case "${choice}" in
    1|"") echo "intel-media-driver" ;;
    2)    echo "libva-intel-driver" ;;
    s|S)  echo "" ;;
    *)    echo "intel-media-driver" ;;
  esac
}

_install_intel_packages() {
  local vaapi_driver="$1"

  # Core 3D & Vulkan
  # ArchWiki: https://wiki.archlinux.org/title/Intel_graphics
  # mesa provides the DRI driver (iris for Gen 8+, crocus for Gen 4-7).
  # vulkan-intel provides the ANV Vulkan driver.
  # ArchWiki note: xf86-video-intel is NOT recommended for modern hardware;
  # modesetting (part of xorg-server / native KMS Wayland) is used by default.
  pacman_install mesa vulkan-intel

  if [[ -n "${vaapi_driver}" ]]; then
    pacman_install "${vaapi_driver}"
  fi

  # Optional 32-bit multilib support (e.g. Steam, Wine)
  local pacman_conf="${ARCHFORGE_PACMAN_CONF:-/etc/pacman.conf}"
  local multilib_enabled=false
  if grep -qE '^[[:space:]]*\[multilib\]' "${pacman_conf}" 2>/dev/null; then
    multilib_enabled=true
  fi

  if [[ "${multilib_enabled}" == "true" ]]; then
    if confirm "Install lib32 packages for 32-bit application support (e.g. Steam)?" "y"; then
      pacman_install lib32-mesa lib32-vulkan-intel
    fi
  else
    log_warn "multilib repository not enabled in ${pacman_conf} -- lib32 packages unavailable."
    log_info "Enable [multilib] in /etc/pacman.conf and run 'sudo pacman -Syu' to unlock 32-bit support."
  fi
}

_configure_intel_early_kms() {
  local conf="${1:-${ARCHFORGE_MKINITCPIO_CONF:-/etc/mkinitcpio.conf}}"

  if [[ ! -f "${conf}" ]]; then
    log_info "${conf} not found -- skipping mkinitcpio early KMS configuration."
    return 0
  fi

  local current_modules=""
  current_modules="$(grep '^MODULES=' "${conf}" 2>/dev/null || true)"

  if echo "${current_modules}" | grep -qE '^[[:space:]]*MODULES=\([^)]*\bi915\b'; then
    log_info "i915 is already present in mkinitcpio MODULES."
    return 0
  fi

  backup_file "${conf}"
  local tmp_mkini
  tmp_mkini="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp_mkini}'" RETURN

  # Safely insert i915 into MODULES=(...) array
  sed -E 's/^[[:space:]]*MODULES=\([[:blank:]]*(.*)[[:blank:]]*\)/MODULES=(\1 i915)/; s/MODULES=\([[:blank:]]+/MODULES=(/; s/[[:blank:]]+\)/)/; s/[[:blank:]]{2,}/ /g' "${conf}" > "${tmp_mkini}"
  run_cmd sudo cp "${tmp_mkini}" "${conf}"

  log_info "Regenerating initramfs with mkinitcpio -P..."
  if ! run_cmd sudo mkinitcpio -P; then
    log_error "mkinitcpio -P failed! initramfs generation was not completed."
    log_warn "Run 'sudo mkinitcpio -P' manually before rebooting to avoid unbootable systems."
    return 1
  fi
  log_ok "initramfs regenerated with i915 early KMS."
  return 0
}

module_run() {
  module_info
  set +T 2>/dev/null || true

  _check_intel_gpu || return $?

  local vaapi_driver
  vaapi_driver="$(_select_vaapi_driver)"

  log_info "Installing Intel open-source graphics drivers (Mesa & ANV)..."
  _install_intel_packages "${vaapi_driver}"

  # Early KMS (ArchWiki: https://wiki.archlinux.org/title/Intel_graphics#KMS)
  # The default 'kms' hook in mkinitcpio HOOKS usually manages early KMS automatically.
  # Explicitly adding i915 to MODULES is only needed in specific early-init setups.
  if confirm "Add i915 to mkinitcpio MODULES for early KMS (optional, 'kms' hook usually suffices)?" "n"; then
    _configure_intel_early_kms || return 1
  fi

  # Hybrid GPU advice (e.g. Intel iGPU + discrete AMD/NVIDIA)
  if [[ "${DETECTED_GPU:-}" == Multiple* ]] || [[ "$(lspci 2>/dev/null | grep -icE 'vga|3d|display' || true)" -gt 1 ]]; then
    log_info "Hybrid graphics detected (multiple GPUs)."
    log_info "Intel iGPU handles display output; discrete GPU can be used on-demand via offload."
  fi

  # Optional GPU monitoring tool
  if confirm "Install intel-gpu-tools for GPU monitoring (intel_gpu_top)?" "y"; then
    pacman_install intel-gpu-tools
  fi

  log_ok "Intel graphics configuration complete."
  log_info "Verify driver status after reboot: lspci -k | grep -A3 -E 'VGA|3D|Display'"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
