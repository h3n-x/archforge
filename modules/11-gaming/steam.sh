#!/usr/bin/env bash
# modules/11-gaming/steam.sh
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
  MODULE_NAME="Gaming: Steam"
  MODULE_DESC="Install Steam with multilib, Proton/Wine dependencies, optional GameMode and MangoHud"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES="steam"
  MODULE_AUR_PACKAGES=""
  # esync nofile limit is a kernel/PAM configuration, not covered by a specific
  # Arch Wiki article — implemented as a known requirement for Proton/Wine gaming.
  MODULE_WIKI_SOURCE="aur-wiki-steam.txt aur-wiki-steam-troubleshooting.txt aur-wiki-gaming.txt aur-wiki-gamemode.txt aur-wiki-mangohud.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info
  set +T 2>/dev/null || true

  # ── Step 1: Check multilib ─────────────────────────────────────────────────
  # Steam requires 32-bit libraries from the multilib repository.
  if ! grep -qE '^\[multilib\]' /etc/pacman.conf 2>/dev/null; then
    log_error "The [multilib] repository is not enabled in /etc/pacman.conf."
    log_error "Steam requires multilib for 32-bit library support."
    log_info "To enable multilib, edit /etc/pacman.conf and uncomment:"
    log_info "  [multilib]"
    log_info "  Include = /etc/pacman.d/mirrorlist"
    log_info "Then run: sudo pacman -Syu"
    return 1
  fi
  log_info "multilib repository is enabled."

  # ── Step 2: Install Steam ──────────────────────────────────────────────────
  # Note: pacman may prompt for the 32-bit Vulkan driver. Choose the one
  # matching your GPU vendor (e.g. lib32-mesa for AMD/Intel, lib32-nvidia-utils
  # for NVIDIA) to avoid Vulkan issues.
  pacman_install steam

  # ── Step 3: Optional Proton/Wine dependencies ──────────────────────────────
  if confirm "Install additional Proton/Wine compatibility libraries (lib32-gtk3, lib32-vulkan-icd-loader, lib32-mesa, lib32-alsa-plugins, vulkan-tools)?" "y"; then
    pacman_install lib32-gtk3 lib32-vulkan-icd-loader lib32-mesa lib32-alsa-plugins vulkan-tools
  fi

  # ── Step 4: File descriptor limit (esync) ─────────────────────────────────
  _configure_fd_limit

  # ── Step 5: vm.max_map_count ──────────────────────────────────────────────
  # Source: aur-wiki-gaming.txt — "Game compatibility / Increase vm.max_map_count"
  _configure_max_map_count

  # ── Step 6: Optional GameMode ─────────────────────────────────────────────
  if confirm "Install GameMode (CPU/GPU performance daemon for gaming)?" "y"; then
    _install_gamemode
  fi

  # ── Step 7: Optional MangoHud ─────────────────────────────────────────────
  if confirm "Install MangoHud (Vulkan/OpenGL in-game performance overlay)?" "y"; then
    _install_mangohud
  fi

  # ── Step 8: NVIDIA-specific advisory ──────────────────────────────────────
  if echo "${DETECTED_GPU:-}" | grep -qi "nvidia"; then
    log_info "NVIDIA GPU detected: for proper 32-bit Vulkan/OpenGL support in Steam games,"
    log_info "install the lib32 variant of your NVIDIA utils package, e.g.:"
    log_info "  lib32-nvidia-utils          (for nvidia / nvidia-open)"
    log_info "  lib32-nvidia-580xx-utils    (for nvidia-580xx-dkms)"
    log_info "  lib32-nvidia-470xx-utils    (for nvidia-470xx-dkms)"
    log_info "Run the Graphics: NVIDIA driver module first if you have not done so."
  fi

  log_ok "Steam installed."
  log_info "Launch Steam from your application menu or run: steam"
}

# ── File descriptor limit (esync) ────────────────────────────────────────────
_configure_fd_limit() {
  # esync requirement — kernel default (1024) is too low for modern games.
  # Proton/Wine esync opens thousands of file descriptors simultaneously;
  # without raising this limit many games fail to launch or crash at startup.
  # Source: https://wiki.archlinux.org/title/Limits.conf
  log_info "Many modern games (Proton/Wine) require high file descriptor limits — kernel default is 1024"

  local current_hard
  current_hard="$(ulimit -Hn 2>/dev/null || echo "unknown")"
  log_info "Current hard file descriptor limit: ${current_hard}"

  local dropin="/etc/security/limits.d/10-esync.conf"

  # Check if already configured in limits.conf or any limits.d drop-in
  if grep -rqsE 'nofile[[:space:]]+524288' /etc/security/limits.conf /etc/security/limits.d/ 2>/dev/null; then
    log_skip "File descriptor limit already configured (nofile 524288 found)"
    return 0
  fi

  if confirm "Set file descriptor limit to 524288 for all users (required by esync)?" "y"; then
    backup_file "${dropin}"
    local tmp
    tmp="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '${tmp}'" RETURN
    cat > "${tmp}" <<'EOF'
# esync requirement — kernel default (1024) is too low for modern games
# ArchWiki: https://wiki.archlinux.org/title/Limits.conf
* hard nofile 524288
* soft nofile 524288
EOF
    run_cmd sudo mkdir -p /etc/security/limits.d
    run_cmd sudo install -Dm644 "${tmp}" "${dropin}"
    log_ok "File descriptor limit drop-in created (${dropin})."
    log_info "Changes take effect on next login session."
  fi
}

# ── vm.max_map_count ──────────────────────────────────────────────────────────
_configure_max_map_count() {
  # Source: aur-wiki-gaming.txt — "Game compatibility / Increase vm.max_map_count"
  # "Having the vm.max_map_count set to a low value can affect the stability
  #  and performance of some games."
  # SteamOS uses 2147483642 (MAX_INT - 5); Arch default is 1048576.
  local sysctl_file="/etc/sysctl.d/80-gamecompatibility.conf"

  if [[ -f "${sysctl_file}" ]] && grep -q 'vm.max_map_count' "${sysctl_file}" 2>/dev/null; then
    log_skip "vm.max_map_count already configured in ${sysctl_file}"
    return 0
  fi

  log_info "vm.max_map_count: low values cause instability in some games (e.g. Hogwarts Legacy, Death Stranding)."
  log_info "SteamOS default: 2147483642 — Arch default: 1048576."

  if confirm "Set vm.max_map_count = 2147483642 (SteamOS value, recommended)?" "y"; then
    backup_file "${sysctl_file}"
    local tmp
    tmp="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '${tmp}'" RETURN
    cat > "${tmp}" <<'EOF'
# Game compatibility — source: Arch Wiki Gaming article
# SteamOS default value; prevents stability issues in memory-intensive games.
# Note: may be incompatible with programs that read core dump files.
vm.max_map_count = 2147483642
EOF
    run_cmd sudo cp "${tmp}" "${sysctl_file}"
    run_cmd sudo sysctl --system
    log_ok "vm.max_map_count = 2147483642 applied."
  fi
}

# ── GameMode ──────────────────────────────────────────────────────────────────
_install_gamemode() {
  # Source: aur-wiki-gamemode.txt
  pacman_install gamemode lib32-gamemode

  # Add current user to gamemode group — required for CPU governor and process
  # niceness changes. Source: aur-wiki-gamemode.txt — "Add yourself to the
  # gamemode user group. Without it, the GameMode user daemon will not have
  # rights to change CPU governor or the niceness of processes."
  local current_user="${SUDO_USER:-${USER:-}}"
  if [[ -n "${current_user}" && "${current_user}" != "root" ]]; then
    if groups "${current_user}" 2>/dev/null | grep -qw gamemode; then
      log_skip "User '${current_user}' is already in the gamemode group."
    else
      run_cmd sudo gpasswd -a "${current_user}" gamemode
      log_info "User '${current_user}' added to gamemode group — re-login required for group to take effect."
    fi
  fi

  # Create system-wide GameMode config.
  # Source: aur-wiki-gamemode.txt — Configuration section.
  # Important: [gpu] settings ONLY take effect from /etc/gamemode.ini —
  # user-local configs are considered "unsafe" for GPU overclocking.
  local gamemode_conf="/etc/gamemode.ini"
  if [[ -f "${gamemode_conf}" ]]; then
    log_skip "${gamemode_conf} already exists — not overwriting."
  else
    if confirm "Create /etc/gamemode.ini with performance settings?" "y"; then
      backup_file "${gamemode_conf}"
      local tmp
      tmp="$(mktemp)"
      # shellcheck disable=SC2064
      trap "rm -f '${tmp}'" RETURN
      cat > "${tmp}" <<'EOF'
# /etc/gamemode.ini — GameMode system configuration
# Source: aur-wiki-gamemode.txt (Arch Wiki GameMode article)
# Full example with all options: https://github.com/FeralInteractive/gamemode

[general]
; GameMode renices the game process using a positive value (then negated):
; renice=10 applies a niceness of -10 (higher CPU priority for the game).
; Default is 0 (no renicing). Max without PAM changes: 10.
renice=10

; Interval (ms) at which GameMode checks if the requesting game is still running.
reaper_freq=5000

[filter]
; Whitelist/blacklist processes by name. Leave empty to allow all.
whitelist=
blacklist=

; ── GPU overclocking (disabled by default) ────────────────────────────────────
; Source: aur-wiki-gamemode.txt — Overclocking section.
; GPU settings require manual setup and only take effect from /etc/gamemode.ini.
; Uncomment and configure for your GPU vendor after reading the wiki.
;
; [gpu]
; apply_gpu_optimizations=accept-responsibility
; gpu_device=0
;
; AMD:
; amd_performance_level=high
;
; NVIDIA:
; nv_powermizer_mode=1
; nv_core_clock_mhz_offset=0
; nv_mem_clock_mhz_offset=0
EOF
      run_cmd sudo cp "${tmp}" "${gamemode_conf}"
      log_ok "GameMode configuration written to ${gamemode_conf}."
    fi
  fi

  # gamemoded.service is started on demand by dbus — do NOT enable manually.
  # Source: aur-wiki-gamemode.txt — "The gamemoded.service user unit is started
  # on demand by dbus."
  log_info "gamemoded starts automatically on demand — no manual service enable needed."
  log_info "Verify your configuration with: gamemoded -t"
  log_ok "GameMode installed."
  log_info "Steam launch option: gamemoderun %command%"
}

# ── MangoHud ──────────────────────────────────────────────────────────────────
_install_mangohud() {
  # Source: aur-wiki-mangohud.txt
  # lib32-mangohud is required for 32-bit game support.
  pacman_install mangohud lib32-mangohud

  # Resolve target user's home directory when running under sudo
  local target_user="${SUDO_USER:-${USER:-}}"
  local user_home="${HOME}"
  if [[ -n "${target_user}" && "${target_user}" != "root" ]]; then
    user_home="$(getent passwd "${target_user}" | cut -d: -f6)"
  fi

  # Config path: $XDG_CONFIG_HOME/MangoHud/MangoHud.conf
  # Source: aur-wiki-mangohud.txt — "MangoHud is configured via the following
  # files: $XDG_CONFIG_HOME/MangoHud/MangoHud.conf"
  local mangohud_dir="${user_home}/.config/MangoHud"
  local mangohud_conf="${mangohud_dir}/MangoHud.conf"

  if [[ -f "${mangohud_conf}" ]]; then
    log_skip "${mangohud_conf} already exists — not overwriting."
  else
    if confirm "Create MangoHud configuration (~/.config/MangoHud/MangoHud.conf)?" "y"; then
      local tmp
      tmp="$(mktemp)"
      # shellcheck disable=SC2064
      trap "rm -f '${tmp}'" RETURN
      cat > "${tmp}" <<'EOF'
# MangoHud configuration — $XDG_CONFIG_HOME/MangoHud/MangoHud.conf
# Source: aur-wiki-mangohud.txt (Arch Wiki MangoHud article)
# Full parameter reference: https://github.com/flightlessmango/MangoHud#config-file
#
# Keyboard shortcuts (defaults):
#   RShift+F12  — Toggle overlay on/off
#   RShift+F11  — Change overlay position
#   RShift+F10  — Toggle preset
#   LShift+F2   — Toggle logging

# ── Frametiming ───────────────────────────────────────────────────────────────
fps
frametime
frame_timing=1

# ── CPU ───────────────────────────────────────────────────────────────────────
cpu_stats
cpu_temp
cpu_mhz

# ── GPU ───────────────────────────────────────────────────────────────────────
gpu_stats
gpu_temp
vram

# ── Memory ────────────────────────────────────────────────────────────────────
ram

# ── Position ──────────────────────────────────────────────────────────────────
position=top-left
EOF
      if [[ -n "${target_user}" && "${target_user}" != "root" ]]; then
        run_cmd sudo install -D -o "${target_user}" -m 644 "${tmp}" "${mangohud_conf}"
      else
        run_cmd install -D -m 644 "${tmp}" "${mangohud_conf}"
      fi
      log_ok "MangoHud configuration written to ${mangohud_conf}."
    fi
  fi

  log_ok "MangoHud installed."
  log_info "Steam launch options:"
  log_info "  Overlay only:   mangohud %command%"
  log_info "  With GameMode:  mangohud gamemoderun %command%"
  # Source: aur-wiki-mangohud.txt — "Enable for all Vulkan games"
  log_info "Enable for all Vulkan games via environment variable: MANGOHUD=1"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
