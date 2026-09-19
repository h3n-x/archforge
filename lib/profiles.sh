#!/usr/bin/env bash
# lib/profiles.sh — high-level profile management and hardware-aware resolution
# shellcheck shell=bash
set -euo pipefail

# ── Available Profiles ────────────────────────────────────────────────────────
PROFILES_AVAILABLE=("server" "desktop-minimal" "desktop-full" "gaming")

declare -A PROFILE_DESCRIPTIONS=(
  ["server"]="Headless server, VPS or Home Lab (core system, network, DNS, firewall, security, optimizations)"
  ["desktop-minimal"]="Lightweight desktop / TWM base (Hyprland/Sway/i3, audio, input, fonts, DNS, firewall)"
  ["desktop-full"]="Full daily workstation (desktop-minimal + Bluetooth, CUPS printing, sensors)"
  ["gaming"]="Optimized gaming PC (Steam, Proton, low-latency audio, Bluetooth gamepads, performance sysctls)"
)

# Base software modules (curated, hardware-agnostic)
declare -A PROFILE_BASE_MODULES=(
  ["server"]="pacman aur-helper systemd users-groups network dns firewall antivirus locale ssd performance"
  ["desktop-minimal"]="pacman aur-helper systemd users-groups network dns firewall keyboard locale fonts libinput audio ssd performance"
  ["desktop-full"]="pacman aur-helper systemd users-groups network dns firewall keyboard locale fonts libinput audio bluetooth printing ssd performance"
  ["gaming"]="pacman aur-helper network dns firewall keyboard locale fonts libinput audio bluetooth ssd performance steam"
)

# ── Internal Helpers ──────────────────────────────────────────────────────────
_check_is_laptop() {
  local ps_dir="${ARCHFORGE_POWER_SUPPLY_DIR:-/sys/class/power_supply}"
  local b
  for b in "${ps_dir}"/BAT*; do
    [[ -e "${b}" ]] || continue
    if [[ -f "${b}/type" ]] && grep -qxi 'battery' "${b}/type" 2>/dev/null; then
      if [[ -f "${b}/scope" ]] && grep -qxi 'device' "${b}/scope" 2>/dev/null; then
        continue
      fi
      return 0
    fi
  done
  if command -v hostnamectl &>/dev/null; then
    local chassis
    chassis="$(hostnamectl chassis 2>/dev/null || true)"
    case "${chassis,,}" in
      laptop|notebook|convertible|portable) return 0 ;;
    esac
  fi
  return 1
}

_is_bare_metal() {
  if [[ "${ARCHFORGE_IS_VM:-false}" == "true" ]]; then
    return 1
  fi
  if command -v systemd-detect-virt &>/dev/null; then
    if systemd-detect-virt -q; then
      return 1  # Inside VM or container
    fi
  fi
  return 0  # Bare metal physical host
}

# ── Multi-GPU & Hardware Scanner ──────────────────────────────────────────────
# Performs direct PCI bus inspection independent of single-string DETECTED_GPU.
detect_profile_hardware_modules() {
  local lspci_out=""
  lspci_out="$(lspci 2>/dev/null)" || lspci_out=""
  local gpu_info=""
  gpu_info="$(grep -iE 'vga|3d|display' <<< "${lspci_out}")" || gpu_info=""

  local -a hw=()

  # Multi-GPU support: checks all present display controllers
  if echo "${gpu_info}" | grep -qiE 'amd|radeon'; then
    hw+=("amd")
  fi
  if echo "${gpu_info}" | grep -qi 'intel'; then
    hw+=("intel")
  fi
  if echo "${gpu_info}" | grep -qi 'nvidia'; then
    hw+=("nvidia")
  fi

  # Laptop battery management (TLP + ACPI)
  if [[ "${IS_LAPTOP:-false}" == "true" ]] || _check_is_laptop; then
    hw+=("tlp" "acpid")
  fi

  # Physical hardware sensors (bare metal only)
  if _is_bare_metal; then
    hw+=("sensors")
  fi

  printf '%s\n' "${hw[@]}"
}

# ── Profile Resolver ──────────────────────────────────────────────────────────
# Resolves a profile into a deduplicated, ordered list of module IDs.
# Usage: resolve_profile <profile_name> <no_hardware_detect> [extra_modules...]
resolve_profile() {
  local profile_name="$1"
  local no_hardware_detect="${2:-false}"
  shift 2 || true
  local -a extra_modules=("$@")

  # 1. Validate profile name
  local valid=false
  local p
  for p in "${PROFILES_AVAILABLE[@]}"; do
    if [[ "${p}" == "${profile_name}" ]]; then
      valid=true
      break
    fi
  done

  if [[ "${valid}" != "true" ]]; then
    echo "Error: Unknown profile '${profile_name}'." >&2
    echo "Available profiles:" >&2
    for p in "${PROFILES_AVAILABLE[@]}"; do
      printf "  %-16s %s\n" "${p}" "${PROFILE_DESCRIPTIONS[${p}]}" >&2
    done
    return 1
  fi

  # 2. Gather base software modules
  local -a resolved=()
  read -r -a resolved <<< "${PROFILE_BASE_MODULES[${profile_name}]}"

  # 3. Auto-incorporate hardware modules (if enabled)
  local -a hw_detected=()
  if [[ "${no_hardware_detect}" != "true" ]]; then
    mapfile -t hw_detected < <(detect_profile_hardware_modules)
    local mod
    for mod in "${hw_detected[@]}"; do
      [[ -z "${mod}" ]] && continue
      # Server profile filter: do not auto-inject GPU or laptop modules into server
      if [[ "${profile_name}" == "server" ]]; then
        case "${mod}" in
          amd|intel|nvidia|nouveau|tlp|acpid) continue ;;
        esac
      fi
      # Gaming profile filter: gaming does not need laptop TLP/acpid automatically unless requested
      if [[ "${profile_name}" == "gaming" ]]; then
        case "${mod}" in
          tlp|acpid|sensors) continue ;;
        esac
      fi
      resolved+=("${mod}")
    done
  fi

  # 4. Merge extra modules from CLI --modules
  if [[ ${#extra_modules[@]} -gt 0 ]]; then
    resolved+=("${extra_modules[@]}")
  fi

  # 5. Gaming safeguard check
  if [[ "${profile_name}" == "gaming" && "${no_hardware_detect}" == "true" ]]; then
    local has_gpu=false
    local m
    for m in "${resolved[@]}"; do
      case "${m}" in
        amd|intel|nvidia|nouveau) has_gpu=true; break ;;
      esac
    done
    if [[ "${has_gpu}" != "true" ]]; then
      log_warn "Profile 'gaming' selected with --no-hardware-detect and no GPU driver in --modules."
      log_warn "Steam requires 3D/Vulkan acceleration. Ensure graphics drivers are pre-installed."
      if [[ "${YES_FLAG:-false}" != "true" && "${DRY_RUN:-false}" != "true" && "${ARCHFORGE_TEST:-false}" != "true" ]]; then
        if ! confirm "Proceed with gaming profile without GPU drivers?"; then
          log_skip "Gaming profile setup cancelled by user."
          return 2
        fi
      fi
    fi
  fi

  # 6. Automatic dependency resolution (MODULE_DEPENDS)
  local -a final_set=()
  local -A seen=()
  for m in "${resolved[@]}"; do
    [[ -z "${m}" ]] && continue
    if [[ -z "${seen[${m}]:-}" ]]; then
      seen["${m}"]=1
      final_set+=("${m}")
    fi
  done

  # Inspect MODULE_DEPENDS for any required dependencies
  local mod_id
  for mod_id in "${final_set[@]}"; do
    local mod_file=""
    if declare -f _find_module_file &>/dev/null; then
      mod_file="$(_find_module_file "${mod_id}" 2>/dev/null || true)"
    elif [[ -n "${ARCHFORGE_DIR:-}" ]]; then
      mod_file="$(find "${ARCHFORGE_DIR}/modules" -name "${mod_id}.sh" 2>/dev/null | head -1 || true)"
    fi

    if [[ -n "${mod_file}" && -f "${mod_file}" ]]; then
      local dep_line
      dep_line="$(grep -E '^[[:space:]]*MODULE_DEPENDS=' "${mod_file}" 2>/dev/null || true)"
      if [[ -n "${dep_line}" ]]; then
        local raw_deps
        raw_deps="${dep_line#*MODULE_DEPENDS=}"
        raw_deps="${raw_deps%\"}"
        raw_deps="${raw_deps#\"}"
        raw_deps="${raw_deps%\'}"
        raw_deps="${raw_deps#\'}"
        local dep
        for dep in ${raw_deps}; do
          if [[ -n "${dep}" && -z "${seen[${dep}]:-}" ]]; then
            seen["${dep}"]=1
            final_set+=("${dep}")
          fi
        done
      fi
    fi
  done

  # 7. Sort strictly by MODULE_EXECUTION_ORDER
  local -a ordered=()
  local target_order=()
  if [[ -n "${MODULE_EXECUTION_ORDER[*]:-}" ]]; then
    target_order=("${MODULE_EXECUTION_ORDER[@]}")
  else
    target_order=(
      "pacman" "aur-helper"
      "systemd" "users-groups"
      "dns" "firewall" "antivirus"
      "network"
      "tlp" "acpid"
      "ssd" "performance" "sensors"
      "libinput" "keyboard"
      "fonts" "locale"
      "amd" "intel" "nouveau" "nvidia"
      "steam"
      "audio" "bluetooth" "printing"
      "vmware-host"
    )
  fi

  for mod in "${target_order[@]}"; do
    if [[ -n "${seen[${mod}]:-}" ]]; then
      ordered+=("${mod}")
      unset "seen[${mod}]"
    fi
  done

  # Append any remaining modules not in standard execution order
  for mod in "${final_set[@]}"; do
    if [[ -n "${seen[${mod}]:-}" ]]; then
      ordered+=("${mod}")
    fi
  done

  printf '%s\n' "${ordered[@]}"
}
