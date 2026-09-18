#!/usr/bin/env bash
# lib/core.sh — logging, confirm(), run_cmd(), global helpers
# shellcheck shell=bash

# ── Colors ────────────────────────────────────────────────────────────────────
_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[1;33m'
_CYAN='\033[0;36m'
_MAGENTA='\033[0;35m'
_DIM='\033[2m'
_RESET='\033[0m'
_BOLD='\033[1m'

# ── Log helpers ───────────────────────────────────────────────────────────────
_log() {
  local tag="${1}" color="${2}" msg="${3}"
  local line
  printf -v line "${color}[%6s]${_RESET} %s" "${tag}" "${msg}"
  echo -e "${line}"
  if [[ -n "${LOG_FILE:-}" ]]; then
    local _ts; _ts="$(date '+%H:%M:%S')"
    echo "[${_ts}] [${tag}] ${msg}" >> "${LOG_FILE}"
  fi
}

log_info()  { _log " INFO " "${_CYAN}"    "$1"; }
log_ok()    { _log "  OK  " "${_GREEN}"   "$1"; }
log_warn()  { _log " WARN " "${_YELLOW}"  "$1" >&2; }
log_error() { _log "ERROR " "${_RED}"     "$1" >&2; }
log_skip()  { _log " SKIP " "${_DIM}"     "$1"; }
log_dry()   { _log "DRYRUN" "${_MAGENTA}" "$1"; }

# ── resolve_log_file ──────────────────────────────────────────────────────────
resolve_log_file() {
  local ts
  ts="$(date '+%Y-%m-%d_%H%M%S')"
  local system_dir='/var/log/archforge'
  local user_dir="${HOME}/.local/share/archforge/logs"

  if mkdir -p "${system_dir}" 2>/dev/null && [[ -w "${system_dir}" ]]; then
    chmod 755 "${system_dir}" 2>/dev/null || true
    LOG_FILE="${system_dir}/${ts}.log"
  else
    mkdir -p "${user_dir}"
    chmod 700 "${user_dir}" 2>/dev/null || true
    LOG_FILE="${user_dir}/${ts}.log"
  fi
  touch "${LOG_FILE}"
  chmod 600 "${LOG_FILE}" 2>/dev/null || true
  export LOG_FILE
}

# ── confirm ───────────────────────────────────────────────────────────────────
# Returns 0 (proceed) or 1 (skip).
# In dry-run or --yes mode: always returns 0 without prompting.
# $2: default answer — "y" → [Y/n] (Enter = yes), "n"/omitted → [y/N] (Enter = no)
# Rationale: dry-run needs confirm() to return 0 so execution reaches run_cmd(),
# where the actual no-execute behavior is enforced via [DRY-RUN] output.
confirm() {
  local prompt="${1:-Continue?}"
  local default="${2:-n}"
  if [[ "${YES_FLAG:-false}" == "true" ]] || [[ "${DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi
  local answer bracket
  if [[ "${default,,}" == "y" ]]; then
    bracket="[Y/n]"
  else
    bracket="[y/N]"
  fi
  read -r -p "$(echo -e "${_BOLD}${prompt}${_RESET} ${bracket} ")" answer
  if [[ -z "${answer}" ]]; then
    [[ "${default,,}" == "y" ]]; return
  fi
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# ── run_cmd ───────────────────────────────────────────────────────────────────
# Central execution wrapper.
# In normal mode: executes command directly, streaming stdout/stderr to LOG_FILE if set.
# In dry-run mode: prints [DRY-RUN] and the command, does not execute.
# In test mode (ARCHFORGE_TEST=true): appends command to MOCK_LOG_FILE on disk.
run_cmd() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_dry "$*"
    return 0
  fi
  if [[ "${ARCHFORGE_TEST:-false}" == "true" ]]; then
    echo "$*" >> "${MOCK_LOG_FILE:-/tmp/archforge-mock-$$.log}"
    return 0
  fi
  if [[ -n "${LOG_FILE:-}" ]]; then
    if [[ ! -e "${LOG_FILE}" ]]; then
      touch "${LOG_FILE}" 2>/dev/null || true
      chmod 600 "${LOG_FILE}" 2>/dev/null || true
    fi
    if [[ -w "${LOG_FILE}" ]]; then
      local _ts
      _ts="$(date '+%Y-%m-%d %H:%M:%S')"
      echo "[${_ts}] [EXEC  ] $*" >> "${LOG_FILE}"
      "$@" 2>&1 | tee -a "${LOG_FILE}"
      local pipe_status=("${PIPESTATUS[@]}")
      return "${pipe_status[0]}"
    fi
  fi
  "$@"
}


# ── die ───────────────────────────────────────────────────────────────────────
die() {
  log_error "$1"
  exit "${2:-1}"
}

# ── require_root ──────────────────────────────────────────────────────────────
require_root() {
  [[ "${EUID}" -eq 0 ]] || die "This operation requires root. Re-run with sudo."
}

# ── sudo keepalive ────────────────────────────────────────────────────────────
_SUDO_KEEPALIVE_PID=""

start_sudo_keepalive() {
  if [[ "${ARCHFORGE_TEST:-false}" == "true" ]] || [[ "${DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi
  if command -v sudo &>/dev/null && [[ -t 0 ]]; then
    if sudo -v 2>/dev/null; then
      (
        while true; do
          sleep 60
          sudo -n -v 2>/dev/null || exit 0
        done
      ) &
      _SUDO_KEEPALIVE_PID=$!
    fi
  fi
}

stop_sudo_keepalive() {
  if [[ -n "${_SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "${_SUDO_KEEPALIVE_PID}" 2>/dev/null || true
    wait "${_SUDO_KEEPALIVE_PID}" 2>/dev/null || true
    _SUDO_KEEPALIVE_PID=""
  fi
}

# ── syntax validation helpers ─────────────────────────────────────────────────
validate_fstab() {
  local fstab_file="$1"
  if [[ ! -s "${fstab_file}" ]]; then
    log_error "fstab validation failed: file is empty (${fstab_file})"
    return 1
  fi
  # Must contain root mount point (/)
  if ! awk '$2 == "/" { found=1 } END { exit !found }' "${fstab_file}"; then
    log_error "fstab validation failed: missing root mount point (/) in ${fstab_file}"
    return 1
  fi
  # Validate column count for non-comment, non-empty lines (must have exactly 6 fields)
  local invalid_lines
  invalid_lines="$(awk 'NF && !/^[[:space:]]*#/ && NF != 6 { print NR ": " $0 }' "${fstab_file}")"
  if [[ -n "${invalid_lines}" ]]; then
    log_error "fstab syntax validation failed (expected 6 columns):\n${invalid_lines}"
    return 1
  fi
  if command -v findmnt &>/dev/null; then
    local out
    out="$(findmnt --verify --tab-file "${fstab_file}" 2>&1 || true)"
    if echo "${out}" | grep -Eiq '[1-9][0-9]* parse error'; then
      log_error "fstab parse error detected:\n${out}"
      return 1
    fi
  fi
  return 0
}

validate_nftables() {
  local nft_file="$1"
  if [[ ! -s "${nft_file}" ]]; then
    log_error "nftables validation failed: file is empty (${nft_file})"
    return 1
  fi
  if command -v nft &>/dev/null; then
    local out
    if [[ "${DRY_RUN:-false}" == "true" || "${ARCHFORGE_TEST:-false}" == "true" ]]; then
      # Mode: DRY-RUN or TEST — never prompt for interactive sudo password
      if [[ "${EUID}" -eq 0 ]]; then
        if ! out="$(nft -c -f "${nft_file}" 2>&1)"; then
          log_error "nftables syntax check failed for ${nft_file}:\n${out}"
          return 1
        fi
      elif sudo -n true 2>/dev/null; then
        if ! out="$(sudo -n nft -c -f "${nft_file}" 2>&1)"; then
          log_error "nftables syntax check failed for ${nft_file}:\n${out}"
          return 1
        fi
      else
        log_dry "[dry-run] skipped privileged nft syntax check (run with sudo to validate against kernel netfilter)"
        return 0
      fi
    else
      # Mode: REAL EXECUTION (DRY_RUN=false, ARCHFORGE_TEST=false)
      if [[ "${EUID}" -eq 0 ]]; then
        if ! out="$(nft -c -f "${nft_file}" 2>&1)"; then
          log_error "nftables syntax check failed for ${nft_file}:\n${out}"
          return 1
        fi
      elif sudo -n true 2>/dev/null; then
        if ! out="$(sudo -n nft -c -f "${nft_file}" 2>&1)"; then
          log_error "nftables syntax check failed for ${nft_file}:\n${out}"
          return 1
        fi
      elif [[ -t 0 ]]; then
        log_info "Validating nftables ruleset syntax (requires sudo)..."
        if ! out="$(sudo nft -c -f "${nft_file}" 2>&1)"; then
          log_error "nftables syntax check failed for ${nft_file}:\n${out}"
          return 1
        fi
      else
        log_error "nftables validation requires sudo privileges, but no active sudo session is available."
        return 1
      fi
    fi
  fi
  return 0
}

# ── Module file resolver ──────────────────────────────────────────────────────
# Resolves a module identifier (e.g. 'nvidia') or file path strictly within modules/.
# Rejects any path outside ARCHFORGE_DIR/modules, including path traversal attempts.
_find_module_file() {
  local target="$1"
  [[ -z "${target}" ]] && return 1

  local modules_dir
  modules_dir="$(realpath -q "${ARCHFORGE_DIR:-.}/modules" 2>/dev/null || true)"
  [[ -z "${modules_dir}" || ! -d "${modules_dir}" ]] && return 1

  # If target is an existing path, canonicalize and verify strict confinement in modules/
  if [[ -e "${target}" ]]; then
    local canon_target
    canon_target="$(realpath -q "${target}" 2>/dev/null || true)"
    if [[ -n "${canon_target}" && -f "${canon_target}" && "${canon_target}" == "${modules_dir}/"* && "${canon_target}" == *.sh ]]; then
      echo "${canon_target}"
      return 0
    fi
    # If path exists but does not resolve inside modules/ or is not .sh, reject immediately
    return 1
  fi

  # Reject any non-existent target containing path traversal characters
  if [[ "${target}" == *"/"* || "${target}" == *".."* ]]; then
    return 1
  fi

  # Resolve from ALL_MODULES mapping
  if [[ -n "${ALL_MODULES+x}" && ${#ALL_MODULES[@]} -gt 0 ]]; then
    local entry
    for entry in "${ALL_MODULES[@]}"; do
      if [[ "${entry%%:*}" == "${target}" ]]; then
        local candidate="${ARCHFORGE_DIR}/modules/${entry#*:}"
        local canon_candidate
        canon_candidate="$(realpath -q "${candidate}" 2>/dev/null || true)"
        if [[ -n "${canon_candidate}" && -f "${canon_candidate}" && "${canon_candidate}" == "${modules_dir}/"* && "${canon_candidate}" == *.sh ]]; then
          echo "${canon_candidate}"
          return 0
        fi
      fi
    done
  fi

  # Fallback search by basename strictly within modules/
  local match
  match="$(find "${modules_dir}" -maxdepth 3 -type f -name "${target}.sh" -print -quit 2>/dev/null || true)"
  if [[ -n "${match}" ]]; then
    local canon_match
    canon_match="$(realpath -q "${match}" 2>/dev/null || true)"
    if [[ -n "${canon_match}" && -f "${canon_match}" && "${canon_match}" == "${modules_dir}/"* && "${canon_match}" == *.sh ]]; then
      echo "${canon_match}"
      return 0
    fi
  fi

  return 1
}


# ── wiki_source_to_urls ───────────────────────────────────────────────────────
# Map MODULE_WIKI_SOURCE filenames to official ArchWiki URLs.
# Usage: wiki_source_to_urls "file1.txt file2.txt"
# Prints one URL (or fallback filename) per line.
wiki_source_to_urls() {
  local sources="${1}"
  local fname url
  for fname in ${sources}; do
    case "${fname}" in
      aur-wiki-amd-graphics.txt)                         url="https://wiki.archlinux.org/title/AMDGPU" ;;
      aur-wiki-arch-boot-process.txt)                    url="https://wiki.archlinux.org/title/Arch_boot_process" ;;
      aur-wiki-CUPS-Printer-specific-problems.txt)       url="https://wiki.archlinux.org/title/CUPS/Printer-specific_problems" ;;
      aur-wiki-CUPS-Troubleshooting.txt)                 url="https://wiki.archlinux.org/title/CUPS/Troubleshooting" ;;
      aur-wiki-CUPS.txt)                                 url="https://wiki.archlinux.org/title/CUPS" ;;
      aur-wiki-dnssec.txt)                               url="https://wiki.archlinux.org/title/DNSSEC" ;;
      aur-wiki-domain-name-resolution.txt)               url="https://wiki.archlinux.org/title/Domain_name_resolution" ;;
      aur-wiki-fan-speed-control.txt)                    url="https://wiki.archlinux.org/title/Fan_speed_control" ;;
      aur-wiki-fonts.txt)                                url="https://wiki.archlinux.org/title/Fonts" ;;
      aur-wiki-general-recommendation.txt)               url="https://wiki.archlinux.org/title/General_recommendations" ;;
      aur-wiki-graphics-processing.txt)                  url="https://wiki.archlinux.org/title/Graphics_processing_unit" ;;
      aur-wiki-improving-performance.txt)                url="https://wiki.archlinux.org/title/Improving_performance" ;;
      aur-wiki-intel-graphics.txt)                       url="https://wiki.archlinux.org/title/Intel_graphics" ;;
      aur-wiki-iptables.txt)                             url="https://wiki.archlinux.org/title/Iptables" ;;
      aur-wiki-laptop-hp.txt)                            url="https://wiki.archlinux.org/title/Laptop/HP" ;;
      aur-wiki-laptop.txt)                               url="https://wiki.archlinux.org/title/Laptop" ;;
      aur-wiki-libinput.txt)                             url="https://wiki.archlinux.org/title/Libinput" ;;
      aur-wiki-linux-console-keyboard-configuration.txt) url="https://wiki.archlinux.org/title/Linux_console/Keyboard_configuration" ;;
      aur-wiki-Linux-console.txt)                        url="https://wiki.archlinux.org/title/Linux_console" ;;
      aur-wiki-lm-sensors.txt)                           url="https://wiki.archlinux.org/title/Lm_sensors" ;;
      aur-wiki-makepkg.txt)                              url="https://wiki.archlinux.org/title/Makepkg" ;;
      aur-wiki-metric-compatible-fonts.txt)              url="https://wiki.archlinux.org/title/Metric-compatible_fonts" ;;
      aur-wiki-mirrors.txt)                              url="https://wiki.archlinux.org/title/Mirrors" ;;
      aur-wiki-mouse-buttons.txt)                        url="https://wiki.archlinux.org/title/Mouse_buttons" ;;
      aur-wiki-network-configuration.txt)                url="https://wiki.archlinux.org/title/Network_configuration" ;;
      aur-wiki-nftables.txt)                             url="https://wiki.archlinux.org/title/Nftables" ;;
      aur-wiki-nouveau.txt)                              url="https://wiki.archlinux.org/title/Nouveau" ;;
      aur-wiki-nvidia.txt)                               url="https://wiki.archlinux.org/title/NVIDIA" ;;
      aur-wiki-official-repositories.txt)                url="https://wiki.archlinux.org/title/Official_repositories" ;;
      aur-wiki-optimus.txt)                              url="https://wiki.archlinux.org/title/NVIDIA_Optimus" ;;
      aur-wiki-pacman-tips-and-tricks.txt)               url="https://wiki.archlinux.org/title/Pacman/Tips_and_tricks" ;;
      aur-wiki-pacman.txt)                               url="https://wiki.archlinux.org/title/Pacman" ;;
      aur-wiki-power-managements.txt)                    url="https://wiki.archlinux.org/title/Power_management" ;;
      aur-wiki-security.txt)                             url="https://wiki.archlinux.org/title/Security" ;;
      aur-wiki-solid-state-drive.txt)                    url="https://wiki.archlinux.org/title/Solid_state_drive" ;;
      aur-wiki-steam-game-specific-troubleshooting.txt)  url="https://wiki.archlinux.org/title/Steam/Game-specific_troubleshooting" ;;
      aur-wiki-steam-troubleshooting.txt)                url="https://wiki.archlinux.org/title/Steam/Troubleshooting" ;;
      aur-wiki-steam.txt)                                url="https://wiki.archlinux.org/title/Steam" ;;
      aur-wiki-systemd.txt)                              url="https://wiki.archlinux.org/title/Systemd" ;;
      aur-wiki-tlp.txt)                                  url="https://wiki.archlinux.org/title/TLP" ;;
      aur-wiki-TrackPoint.txt)                           url="https://wiki.archlinux.org/title/TrackPoint" ;;
      aur-wiki-unified-extensible-firmware-interface.txt) url="https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface" ;;
      aur-wiki-user-and-groups.txt)                      url="https://wiki.archlinux.org/title/Users_and_groups" ;;
      aur-wiki-vmware-install-arch-linux-as-a-guest.txt) url="https://wiki.archlinux.org/title/VMware/Install_Arch_Linux_as_a_guest" ;;
      aur-wiki-vmware.txt)                               url="https://wiki.archlinux.org/title/VMware" ;;
      aur-wiki-xorg-keyboard-configuration.txt)          url="https://wiki.archlinux.org/title/Xorg/Keyboard_configuration" ;;
      aur-wiki-xorg.txt)                                 url="https://wiki.archlinux.org/title/Xorg" ;;
      *)                                                 url="${fname}" ;;  # fallback: show filename
    esac
    echo "${url}"
  done
}
