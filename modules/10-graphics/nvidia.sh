#!/usr/bin/env bash
# modules/10-graphics/nvidia.sh
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
  MODULE_NAME="Graphics: NVIDIA driver"
  MODULE_DESC="Install NVIDIA driver (proprietary or open-source), DRM KMS, optional Optimus support"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN="NVIDIA GPU required"
  MODULE_PACKAGES=""
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-nvidia.txt aur-wiki-optimus.txt aur-wiki-graphics-processing.txt"
  MODULE_DEPENDS=""
}

# ── GPU family detection ─────────────────────────────────────────────────────
# Returns a family string: blackwell, ada, ampere, turing, volta, pascal,
# maxwell2, maxwell1, kepler, fermi, tesla, or "unknown".
_detect_nvidia_family() {
  local lspci_output device_ids family

  lspci_output="$(lspci -nn -d 10de: 2>/dev/null)" || lspci_output=""
  if [[ -z "${lspci_output}" ]]; then
    echo "unknown"
    return 0
  fi

  # Extract 4-digit hex device IDs from [10de:XXXX]
  device_ids="$(echo "${lspci_output}" | grep -oP '\[10de:\K[0-9a-fA-F]{4}' || true)"
  if [[ -z "${device_ids}" ]]; then
    echo "unknown"
    return 0
  fi

  # Check device IDs against known ranges (first VGA/3D device wins)
  local did
  for did in ${device_ids}; do
    local dec
    dec=$(( 16#${did} ))

    # Blackwell: 0x2c00-0x2fff
    if (( dec >= 0x2c00 && dec <= 0x2fff )); then
      echo "blackwell"; return 0
    fi
    # Ada Lovelace: 0x2600-0x27ff
    if (( dec >= 0x2600 && dec <= 0x27ff )); then
      echo "ada"; return 0
    fi
    # Ampere: 0x2200-0x25ff
    if (( dec >= 0x2200 && dec <= 0x25ff )); then
      echo "ampere"; return 0
    fi
    # Turing: 0x1e00-0x1fff, 0x2100-0x21ff
    if (( (dec >= 0x1e00 && dec <= 0x1fff) || (dec >= 0x2100 && dec <= 0x21ff) )); then
      echo "turing"; return 0
    fi
    # Volta: 0x1d00-0x1dff
    if (( dec >= 0x1d00 && dec <= 0x1dff )); then
      echo "volta"; return 0
    fi
    # Pascal: 0x1b00-0x1cff
    if (( dec >= 0x1b00 && dec <= 0x1cff )); then
      echo "pascal"; return 0
    fi
    # Maxwell Gen2: 0x17c0-0x17ff, 0x1380-0x13ff, 0x1400-0x17bf
    if (( (dec >= 0x17c0 && dec <= 0x17ff) || (dec >= 0x1380 && dec <= 0x13ff) || (dec >= 0x1400 && dec <= 0x17bf) )); then
      echo "maxwell2"; return 0
    fi
    # Maxwell Gen1: 0x1340-0x137f, 0x1280-0x12ff
    if (( (dec >= 0x1340 && dec <= 0x137f) || (dec >= 0x1280 && dec <= 0x12ff) )); then
      echo "maxwell1"; return 0
    fi
    # Kepler: 0x0fc0-0x0fff, 0x1000-0x107f, 0x1180-0x11ff, 0x0e00-0x0e3f
    if (( (dec >= 0x0fc0 && dec <= 0x0fff) || (dec >= 0x1000 && dec <= 0x107f) || (dec >= 0x1180 && dec <= 0x11ff) || (dec >= 0x0e00 && dec <= 0x0e3f) )); then
      echo "kepler"; return 0
    fi
    # Fermi: 0x0dc0-0x0dff, 0x0e80-0x0ebf, 0x1040-0x107f, 0x1080-0x10bf
    if (( (dec >= 0x0dc0 && dec <= 0x0dff) || (dec >= 0x0e80 && dec <= 0x0ebf) || (dec >= 0x1040 && dec <= 0x107f) || (dec >= 0x1080 && dec <= 0x10bf) )); then
      echo "fermi"; return 0
    fi
    # Tesla: 0x05e0-0x05ff, 0x0600-0x063f, 0x0640-0x067f
    if (( (dec >= 0x05e0 && dec <= 0x05ff) || (dec >= 0x0600 && dec <= 0x063f) || (dec >= 0x0640 && dec <= 0x067f) )); then
      echo "tesla"; return 0
    fi
  done

  # Secondary fallback: substring matching on model name
  local model_line
  model_line="$(echo "${lspci_output}" | grep -iE 'VGA|3D|Display' | head -1 || true)"
  if [[ -n "${model_line}" ]]; then
    if echo "${model_line}" | grep -qiE 'RTX\s*50|RTX\s*5[0-9]{3}'; then
      echo "blackwell"; return 0
    fi
    if echo "${model_line}" | grep -qiE 'RTX\s*40|RTX\s*4[0-9]{3}'; then
      echo "ada"; return 0
    fi
    if echo "${model_line}" | grep -qiE 'RTX\s*30|RTX\s*3[0-9]{3}'; then
      echo "ampere"; return 0
    fi
    if echo "${model_line}" | grep -qiE 'RTX\s*20|RTX\s*2[0-9]{3}|GTX\s*16[0-9]{2}'; then
      echo "turing"; return 0
    fi
    if echo "${model_line}" | grep -qiE 'GTX\s*10[0-9]{2}'; then
      echo "pascal"; return 0
    fi
    if echo "${model_line}" | grep -qiE 'GTX\s*9[0-9]{2}|GTX\s*8[0-9]{2}'; then
      echo "maxwell2"; return 0
    fi
    if echo "${model_line}" | grep -qiE 'GTX\s*7[0-9]{2}|GTX\s*6[0-9]{2}'; then
      echo "kepler"; return 0
    fi
    if echo "${model_line}" | grep -qiE 'GTX\s*5[0-9]{2}|GTX\s*4[0-9]{2}'; then
      echo "fermi"; return 0
    fi
  fi

  echo "unknown"
}

# ── Manual family selection menu ─────────────────────────────────────────────
_select_nvidia_family_manual() {
  local lspci_output
  lspci_output="$(lspci -nn -d 10de: 2>/dev/null)" || lspci_output=""

  echo "" >&2
  if [[ -n "${lspci_output}" ]]; then
    echo "Detected NVIDIA device(s):" >&2
    echo "${lspci_output}" >&2
    echo "" >&2
  fi
  echo "Could not auto-detect GPU family. Select manually:" >&2
  echo "  [1] Blackwell (RTX 50xx, 2024+)         -> nvidia-open" >&2
  echo "  [2] Ada/Ampere/Turing (RTX 20-40xx)     -> nvidia-open or nvidia-580xx-dkms" >&2
  echo "  [3] Pascal/Maxwell/Volta (GTX 900-1600)  -> nvidia-580xx-dkms" >&2
  echo "  [4] Kepler (GTX 600-700)                 -> nvidia-470xx-dkms (unsupported)" >&2
  echo "  [5] Fermi (GTX 400-500)                  -> nvidia-390xx-dkms (unsupported)" >&2
  echo "  [6] Tesla (G80/G90/GT2xx)                -> nvidia-340xx-dkms (obsolete)" >&2
  echo "  [q] Cancel" >&2

  local choice
  read -r -p "Choice: " choice
  case "${choice}" in
    1) echo "blackwell" ;;
    2) echo "ada" ;;
    3) echo "pascal" ;;
    4) echo "kepler" ;;
    5) echo "fermi" ;;
    6) echo "tesla" ;;
    q) echo "" ;;
    *) echo "" ;;
  esac
}

# ── Driver selection ─────────────────────────────────────────────────────────
# Given a family string, returns the driver package base name.
# For families with two options, shows a selection menu.
_select_nvidia_driver() {
  local family="$1"

  case "${family}" in
    blackwell)
      log_info "Blackwell GPU detected -> nvidia-open is the only supported driver."
      echo "nvidia-open"
      ;;
    ada|ampere|turing)
      if [[ "${YES_FLAG:-false}" == "true" || "${DRY_RUN:-false}" == "true" ]]; then
        echo "nvidia-open"
        return 0
      fi
      echo "" >&2
      echo "Select driver for ${family^} GPU:" >&2
      echo "  [1] nvidia-open [* recomendado]  -- open DRM + proprietary userland, NVIDIA upstream preferred" >&2
      echo "  [2] nvidia-580xx-dkms            -- fully proprietary, more stable on some Ampere laptops" >&2
      local choice
      read -r -p "Driver: " choice
      case "${choice}" in
        1) echo "nvidia-open" ;;
        2) echo "nvidia-580xx-dkms" ;;
        *) echo "nvidia-open" ;;
      esac
      ;;
    volta|pascal|maxwell2|maxwell1)
      log_info "${family^} GPU detected -> nvidia-580xx-dkms is the supported driver."
      echo "nvidia-580xx-dkms"
      ;;
    kepler)
      log_warn "Kepler support ended -- driver may not work with latest Xorg"
      echo "nvidia-470xx-dkms"
      ;;
    fermi)
      log_warn "Fermi support ended -- driver may not work with latest Xorg"
      echo "nvidia-390xx-dkms"
      ;;
    tesla)
      log_warn "Tesla driver is obsolete -- very limited functionality"
      echo "nvidia-340xx-dkms"
      ;;
    *)
      log_error "Unknown GPU family: ${family}"
      echo ""
      ;;
  esac
}

# ── Install driver packages ──────────────────────────────────────────────────
_install_driver_packages() {
  local driver="$1"
  local install_lib32=false

  # Check multilib before asking
  local multilib_enabled=false
  if grep -qE '^\[multilib\]' /etc/pacman.conf 2>/dev/null; then
    multilib_enabled=true
  fi

  if [[ "${multilib_enabled}" == "true" ]]; then
    if confirm "Install lib32 packages for 32-bit application support (e.g. Steam)?" "y"; then
      install_lib32=true
    fi
  else
    log_warn "multilib repository not enabled in /etc/pacman.conf -- lib32 packages unavailable."
    log_info "Enable [multilib] in /etc/pacman.conf and run 'sudo pacman -Sy' to unlock 32-bit support."
  fi

  case "${driver}" in
    nvidia-open)
      pacman_install nvidia-open nvidia-utils
      if [[ "${install_lib32}" == "true" ]]; then
        pacman_install lib32-nvidia-utils
      fi
      ;;
    nvidia-580xx-dkms)
      aur_install nvidia-580xx-dkms nvidia-580xx-utils
      if [[ "${install_lib32}" == "true" ]]; then
        aur_install lib32-nvidia-580xx-utils
      fi
      ;;
    nvidia-470xx-dkms)
      aur_install nvidia-470xx-dkms nvidia-470xx-utils
      if [[ "${install_lib32}" == "true" ]]; then
        aur_install lib32-nvidia-470xx-utils
      fi
      ;;
    nvidia-390xx-dkms)
      aur_install nvidia-390xx-dkms nvidia-390xx-utils
      if [[ "${install_lib32}" == "true" ]]; then
        aur_install lib32-nvidia-390xx-utils
      fi
      ;;
    nvidia-340xx-dkms)
      aur_install nvidia-340xx-dkms nvidia-340xx-utils
      if [[ "${install_lib32}" == "true" ]]; then
        aur_install lib32-nvidia-340xx-utils
      fi
      ;;
    *)
      log_error "Unknown driver: ${driver}"
      return 1
      ;;
  esac
}

# ── DRM KMS configuration ───────────────────────────────────────────────────
_configure_drm_kms() {
  local driver="$1"

  # nvidia-open with nvidia-utils >= 560 has DRM enabled by default
  if [[ "${driver}" == "nvidia-open" ]]; then
    local nvidia_ver
    nvidia_ver="$(pacman -Q nvidia-utils 2>/dev/null | awk '{print $2}' | cut -d. -f1 || echo "0")"
    if [[ "${nvidia_ver}" -ge 560 ]]; then
      log_info "nvidia-utils >= 560 detected -- DRM KMS is enabled by default. Skipping modprobe.conf."
      return 0
    fi
  fi

  log_info "Writing DRM KMS modprobe configuration..."
  backup_file "/etc/modprobe.d/nvidia.conf"
  run_cmd sudo tee /etc/modprobe.d/nvidia.conf <<< "options nvidia_drm modeset=1 fbdev=1" > /dev/null

  # Regenerate initramfs
  log_info "Regenerating initramfs -- this may take 1-3 minutes..."
  local t_start t_end elapsed
  t_start=$(date +%s)
  if run_cmd sudo mkinitcpio -P; then
    t_end=$(date +%s)
    elapsed=$(( t_end - t_start ))
    log_ok "initramfs regenerated in ${elapsed}s."
  else
    t_end=$(date +%s)
    elapsed=$(( t_end - t_start ))
    log_error "mkinitcpio -P failed after ${elapsed}s."
    log_warn "Run 'sudo mkinitcpio -P' manually after reboot to complete setup."
    log_warn "The driver is installed but KMS may not load correctly until initramfs is regenerated."
    # Do NOT exit 1 here -- driver is installed, initramfs failure is recoverable
  fi
}

# ── Optimus configuration ───────────────────────────────────────────────────
_configure_optimus() {
  log_info "Optimus laptop detected (Intel+NVIDIA hybrid graphics)"
  log_warn "All Optimus methods are mutually exclusive. If you've used one before, revert it first."

  if [[ "${YES_FLAG:-false}" == "true" || "${DRY_RUN:-false}" == "true" ]]; then
    # Default to EnvyControl in non-interactive mode
    aur_install envycontrol
    run_cmd sudo envycontrol -s hybrid
    log_ok "EnvyControl set to hybrid mode. Reboot required."
    return 0
  fi

  echo "" >&2
  echo "Select Optimus method:" >&2
  echo "  [1] EnvyControl [* recomendado] -- no daemon, no GDM patches, requires reboot" >&2
  echo "  [2] PRIME render offload         -- official NVIDIA method, no extra packages" >&2
  echo "  [3] switcheroo-control           -- D-Bus integration, works with AMD+Intel+NVIDIA" >&2
  echo "  [s] Skip Optimus configuration" >&2

  local choice
  read -r -p "Choice: " choice
  case "${choice}" in
    1)
      aur_install envycontrol
      run_cmd sudo envycontrol -s hybrid
      log_ok "EnvyControl set to hybrid mode. Reboot required."
      log_info "Use 'sudo envycontrol -s [integrated|nvidia|hybrid]' to switch modes."
      ;;
    2)
      log_info "PRIME render offload requires no extra packages."
      log_info "To run an app on NVIDIA GPU:"
      log_info "  __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <app>"
      if confirm "Create /etc/environment.d/90-nvidia-prime-hint.conf with usage instructions?"; then
        run_cmd sudo mkdir -p /etc/environment.d
        run_cmd sudo tee /etc/environment.d/90-nvidia-prime-hint.conf > /dev/null <<'PRIME_EOF'
# NVIDIA PRIME render offload environment variables
# Uncomment to make the NVIDIA GPU the default for all applications:
#__NV_PRIME_RENDER_OFFLOAD=1
#__GLX_VENDOR_LIBRARY_NAME=nvidia
PRIME_EOF
        log_ok "Created /etc/environment.d/90-nvidia-prime-hint.conf"
      fi
      ;;
    3)
      pacman_install switcheroo-control
      run_cmd sudo systemctl enable --now switcheroo-control.service
      log_ok "switcheroo-control enabled. Apps can now request the dedicated GPU via their .desktop PrefersNonDefaultGPU field."
      ;;
    s)
      log_skip "Optimus configuration skipped."
      ;;
    *)
      log_skip "Invalid choice -- skipping Optimus configuration."
      ;;
  esac
}

# ── Main ─────────────────────────────────────────────────────────────────────
module_run() {
  module_info

  # HW_WARN check: require NVIDIA GPU
  if [[ "${DETECTED_GPU:-Unknown}" != *"NVIDIA"* ]]; then
    log_warn "${MODULE_HW_WARN}"
    confirm "No NVIDIA GPU detected. Continue anyway?" || return 2
  fi

  # Detect GPU family
  local family
  family="$(_detect_nvidia_family)"

  if [[ "${family}" == "unknown" ]]; then
    family="$(_select_nvidia_family_manual)"
    [[ -z "${family}" ]] && { log_skip "NVIDIA driver installation cancelled."; return 2; }
  fi

  log_info "Detected GPU family: ${family}"

  # Select driver
  local driver
  driver="$(_select_nvidia_driver "${family}")"
  [[ -z "${driver}" ]] && { log_error "No driver selected."; return 1; }

  log_info "Installing driver: ${driver}"
  confirm "Proceed with ${driver} installation?" || return 2

  # Install packages
  _install_driver_packages "${driver}"

  # Verify the primary driver package actually got installed before
  # proceeding. aur_install() silently no-ops (log_skip, exit 0) when no AUR
  # helper is configured, so without this check a DKMS driver install with
  # no AUR helper present would appear to "succeed" while installing
  # nothing. Skipped under DRY_RUN/ARCHFORGE_TEST, where nothing is ever
  # installed for real. ${driver} is always the primary package name for
  # each case in _install_driver_packages() above.
  if [[ "${DRY_RUN:-false}" != "true" && "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    if ! pkg_installed "${driver}"; then
      log_error "Package '${driver}' was not installed — aborting."
      log_error "If this is an AUR package, make sure an AUR helper is configured (run the 'AUR helper' module first)."
      return 1
    fi
  fi

  # DRM KMS
  _configure_drm_kms "${driver}"

  # Optimus (laptop with hybrid graphics only). IS_LAPTOP alone does not
  # imply a hybrid iGPU+dGPU setup — e.g. an NVIDIA-only gaming laptop with
  # no integrated GPU. lib/detect.sh sets DETECTED_GPU to "Multiple (...)"
  # when more than one GPU is found on the PCI bus.
  if [[ "${IS_LAPTOP:-false}" == "true" && "${DETECTED_GPU:-}" == Multiple* ]]; then
    _configure_optimus
  elif [[ "${IS_LAPTOP:-false}" == "true" ]]; then
    log_info "Laptop detected but no hybrid graphics found (DETECTED_GPU=${DETECTED_GPU:-Unknown}) — skipping Optimus configuration."
  fi

  # Optional nvtop
  confirm "Install nvtop for GPU monitoring?" "y" && pacman_install nvtop

  # Final summary
  log_ok "NVIDIA driver installed. A reboot is required to load the kernel modules."
  if [[ "${IS_LAPTOP:-false}" == "true" ]]; then
    log_info "After reboot, verify GPU status with: nvidia-smi"
  fi
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
