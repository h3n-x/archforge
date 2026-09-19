#!/usr/bin/env bash
# lib/detect.sh — hardware detection, runs once at startup
# shellcheck shell=bash

detect_hardware() {
  # CPU: parse vendor_id from /proc/cpuinfo
  local vendor cpuinfo_line
  cpuinfo_line="$(grep -m1 'vendor_id' /proc/cpuinfo 2>/dev/null)" || cpuinfo_line=''
  vendor="$(awk '{print $3}' <<< "${cpuinfo_line}")"
  case "${vendor}" in
    GenuineIntel) DETECTED_CPU="Intel"   ;;
    AuthenticAMD) DETECTED_CPU="AMD"     ;;
    *)            DETECTED_CPU="Unknown" ;;
  esac
  export DETECTED_CPU

  # GPU: parse lspci output for display controllers
  local gpu_info lspci_out
  lspci_out="$(lspci 2>/dev/null)" || lspci_out=''
  # Evaluation priority order: NVIDIA > AMD > Intel.
  # Rationale: NVIDIA is prioritized as primary because it requires specialized
  # driver stacks, proprietary kernel modules, and explicit Optimus/PRIME
  # offloading configuration that AMD and Intel in-kernel DRM drivers do not need.
  # When multiple display controllers exist, DETECTED_GPU is prefixed with "Multiple (...)".
  # Dedicated GPU modules (amd.sh, intel.sh) perform secondary lspci checks to
  # reliably detect secondary/integrated GPUs in hybrid multi-GPU setups.
  if echo "${gpu_info}" | grep -qi 'nvidia'; then
    DETECTED_GPU="NVIDIA"
  elif echo "${gpu_info}" | grep -qiE 'amd|radeon'; then
    DETECTED_GPU="AMD"
  elif echo "${gpu_info}" | grep -qi 'intel'; then
    DETECTED_GPU="Intel"
  else
    DETECTED_GPU="Unknown"
  fi
  # Detect multiple GPUs (e.g. Optimus laptop)
  local gpu_count
  gpu_count="$(echo "${gpu_info}" | grep -c '.')" || gpu_count=0
  if [[ "${gpu_count}" -gt 1 ]]; then
    DETECTED_GPU="Multiple (${DETECTED_GPU})"
  fi
  export DETECTED_GPU

  # Laptop detection: check for battery in /sys
  if compgen -G "/sys/class/power_supply/BAT*/present" > /dev/null 2>&1; then
    IS_LAPTOP=true
    SYSTEM_TYPE="laptop"
  else
    IS_LAPTOP=false
    SYSTEM_TYPE="desktop"
  fi
  export IS_LAPTOP SYSTEM_TYPE
  export DETECTED_INIT="systemd"
}
