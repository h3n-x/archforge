#!/usr/bin/env bash
# modules/07-optimization/performance.sh
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
  MODULE_NAME="Optimization: Performance"
  MODULE_DESC="vm.swappiness, CPU governor, zram-generator, OOM killer, network sysctls"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES="zram-generator"
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-improving-performance.txt aur-wiki-zram.txt aur-wiki-gaming.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info

  local tmp_sysctl="" tmp_udev="" tmp_zram=""
  trap 'rm -f "${tmp_sysctl}" "${tmp_udev}" "${tmp_zram}"' RETURN

  # ── Base sysctl tweaks ────────────────────────────────────────────────────
  local sysctl_file="/etc/sysctl.d/99-archforge.conf"
  backup_file "${sysctl_file}"
  tmp_sysctl="$(mktemp)"
  cat > "${tmp_sysctl}" <<'EOF'
# archforge base performance tuning
# Source: aur-wiki-improving-performance.txt — Tuning kernel parameters
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
  run_cmd sudo cp "${tmp_sysctl}" "${sysctl_file}"

  # ── Network sysctl tweaks ─────────────────────────────────────────────────
  # Source: aur-wiki-improving-performance.txt — Network section:
  # "Kernel networking: see Sysctl#Improving performance"
  # Note: specific parameters are documented in the Sysctl article referenced
  # by the Improving performance wiki; implemented per user spec.
  _configure_network_sysctls

  # ── Transparent Huge Pages (THP) ──────────────────────────────────────────
  # Source: aur-wiki-gaming.txt — "Improving performance" section (lines 407-411):
  # "Disable Transparent Hugepages (THP) at a performance cost... Enable only
  #  when the application specifically requests it by using madvise and advise."
  # The 'madvise' mode is a safe middle ground: THP only for apps that request it.
  _configure_thp

  # ── CPU governor ──────────────────────────────────────────────────────────
  echo ""
  echo "Select CPU governor:"
  echo "  [1] schedutil [★ recomendado] — kernel-managed, balances performance and power"
  echo "  [2] powersave                 — always use lowest frequency, maximum battery"
  echo "  [3] performance               — always use highest frequency ⚠ higher CPU temperature and power draw"
  local gov_choice gov
  read -r -p "Choice [1]: " gov_choice
  case "${gov_choice:-1}" in
    2) gov="powersave"   ;;
    3) gov="performance" ;;
    *) gov="schedutil"   ;;
  esac
  local udev_file="/etc/udev/rules.d/50-archforge-cpufreq.rules"
  backup_file "${udev_file}"
  tmp_udev="$(mktemp)"
  printf 'ACTION=="add", SUBSYSTEM=="cpu", ATTR{cpufreq/scaling_governor}="%s"\n' "${gov}" > "${tmp_udev}"
  run_cmd sudo cp "${tmp_udev}" "${udev_file}"

  # ── Apply base sysctls now (before zram may override swappiness) ──────────
  _apply_sysctl

  # ── zram ──────────────────────────────────────────────────────────────────
  if confirm "Install and configure zram (compressed swap in RAM)?" "y"; then
    _configure_zram
  fi

  # ── OOM killer ────────────────────────────────────────────────────────────
  # earlyoom is not explicitly mentioned in aur-wiki-improving-performance.txt;
  # systemd-oomd is part of systemd. Both implemented per user spec as known
  # OOM prevention practice for Arch Linux systems.
  _configure_oom_killer

  log_ok "Performance settings applied."
}

# ── Network sysctl tweaks ─────────────────────────────────────────────────────
_configure_network_sysctls() {
  local net_sysctl_file="/etc/sysctl.d/99-archforge-network.conf"

  if [[ -f "${net_sysctl_file}" ]]; then
    log_skip "Network sysctl tweaks already configured in ${net_sysctl_file}."
    return 0
  fi

  echo ""
  echo "Network performance sysctl tweaks:"
  echo "  net.ipv4.tcp_fastopen=3      — reduce TCP handshake latency (client+server)"
  echo "  net.core.netdev_max_backlog  — increase queue for high-speed network adapters"
  echo "  net.ipv4.tcp_tw_reuse=1      — reuse TIME_WAIT sockets for new connections"
  echo "  kernel.nmi_watchdog=0        — disable NMI watchdog, reduces CPU interrupts"
  echo ""

  if confirm "Apply network performance sysctl tweaks?" "y"; then
    backup_file "${net_sysctl_file}"
    local tmp
    tmp="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '${tmp}'" RETURN
    cat > "${tmp}" <<'EOF'
# archforge — network performance tuning
# Source: aur-wiki-improving-performance.txt (references Sysctl#Improving_performance)

# TCP Fast Open: reduces latency by sending data in SYN packets (client+server)
net.ipv4.tcp_fastopen=3

# Increase network adapter receive queue depth for high-throughput adapters
net.core.netdev_max_backlog=16384

# Reuse TIME_WAIT sockets for outbound connections (reduces socket exhaustion)
net.ipv4.tcp_tw_reuse=1

# Disable NMI watchdog — reduces periodic CPU interrupts on desktop systems
kernel.nmi_watchdog=0
EOF
    run_cmd sudo cp "${tmp}" "${net_sysctl_file}"
    log_ok "Network sysctl tweaks written to ${net_sysctl_file}."
  fi
}

# ── Transparent Huge Pages ────────────────────────────────────────────────────
_configure_thp() {
  # Source: aur-wiki-gaming.txt — "Tweaking kernel parameters for response time":
  # "Disable Transparent Hugepages (THP) at a performance cost. Even if
  #  defragmentation is disabled, THPs might introduce latency spikes. Enable
  #  only when the application specifically requests it by using madvise."
  # Using systemd-tmpfiles for persistence (recommended approach in gaming wiki).
  local thp_conf="/etc/tmpfiles.d/archforge-thp.conf"

  if [[ -f "${thp_conf}" ]]; then
    log_skip "THP configuration already present in ${thp_conf}."
    return 0
  fi

  log_info "Transparent Huge Pages (THP): 'madvise' mode enables THP only for apps that request it."
  log_info "This reduces latency jitter compared to 'always', without disabling THP entirely."

  if confirm "Set Transparent Huge Pages to 'madvise' mode?" "y"; then
    backup_file "${thp_conf}"
    local tmp
    tmp="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '${tmp}'" RETURN
    cat > "${tmp}" <<'EOF'
# archforge — Transparent Huge Pages configuration
# Source: aur-wiki-gaming.txt — "Tweaking kernel parameters for response time"
# 'madvise': THP only for applications that explicitly request it via madvise().
# Reduces latency spikes while preserving THP benefits for apps that use it.
#    Path                                        Mode UID GID Age Argument
w    /sys/kernel/mm/transparent_hugepage/enabled  -    -   -   -   madvise
w    /sys/kernel/mm/transparent_hugepage/defrag   -    -   -   -   never
EOF
    run_cmd sudo cp "${tmp}" "${thp_conf}"
    # Apply immediately without reboot. Routed through run_cmd (instead of a
    # raw `sudo tee`) so DRY_RUN and ARCHFORGE_TEST both gate this write —
    # previously this bypassed DRY_RUN and mutated live kernel state even
    # under --dry-run.
    run_cmd sudo tee /sys/kernel/mm/transparent_hugepage/enabled <<< "madvise" > /dev/null 2>&1 || true
    run_cmd sudo tee /sys/kernel/mm/transparent_hugepage/defrag  <<< "never"   > /dev/null 2>&1 || true
    log_ok "THP set to 'madvise' (persisted via systemd-tmpfiles)."
  fi
}

# ── Apply base sysctl ─────────────────────────────────────────────────────────
_apply_sysctl() {
  if [[ "${DRY_RUN:-false}" == "true" || "${ARCHFORGE_TEST:-false}" == "true" ]]; then
    run_cmd sudo sysctl --system
    return 0
  fi
  local sysctl_out
  if ! sysctl_out="$(sudo sysctl --system 2>&1)"; then
    log_error "sysctl --system failed:"
    echo "${sysctl_out}" >&2
  else
    log_info "sysctl parameters applied."
  fi
}

# ── zram configuration ────────────────────────────────────────────────────────
_configure_zram() {
  # Source: aur-wiki-zram.txt — "Using zram-generator"
  pacman_install zram-generator
  backup_file "/etc/systemd/zram-generator.conf"

  local tmp_zram
  tmp_zram="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp_zram}'" RETURN

  # Source: aur-wiki-zram.txt lines 96-127:
  # zram-size = ram / 2 (default, up to 4GiB)
  # compression-algorithm = zstd
  # swap-priority = 100 (wiki: swapon --priority 100, fstab: pri=100)
  cat > "${tmp_zram}" <<'EOF'
# zram-generator configuration
# Source: aur-wiki-zram.txt (Arch Wiki zram article)

[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
swap-priority = 100
EOF
  run_cmd sudo cp "${tmp_zram}" /etc/systemd/zram-generator.conf
  run_cmd sudo systemctl daemon-reload
  run_cmd sudo systemctl start systemd-zram-setup@zram0.service

  # Optimized sysctl values for zram swap.
  # Source: aur-wiki-zram.txt — "Optimizing swap on zram" (lines 168-174):
  # "These values are what Pop!_OS uses... vm.swappiness = 180 is ideal
  #  for in-memory swap... vm.page-cluster = 0 is ideal."
  # Note: This file has higher alphabetical priority than 99-archforge.conf
  # and will override vm.swappiness=10 set there (10 is for disk swap).
  local zram_sysctl="/etc/sysctl.d/99-vm-zram-parameters.conf"
  if [[ ! -f "${zram_sysctl}" ]]; then
    if confirm "Apply optimized sysctl values for zram (swappiness=180, page-cluster=0)?" "y"; then
      log_info "swappiness=180: in-memory swap (zram) is faster than disk — high swappiness is beneficial."
      log_info "page-cluster=0: reads one page at a time from zram (optimal for random access)."
      backup_file "${zram_sysctl}"
      local tmp_zsysctl
      tmp_zsysctl="$(mktemp)"
      # shellcheck disable=SC2064
      trap "rm -f '${tmp_zsysctl}'" RETURN
      cat > "${tmp_zsysctl}" <<'EOF'
# Optimized sysctl values for zram swap
# Source: aur-wiki-zram.txt — "Optimizing swap on zram"
# Overrides vm.swappiness=10 from 99-archforge.conf (zram is in-memory, not disk).
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF
      run_cmd sudo cp "${tmp_zsysctl}" "${zram_sysctl}"
      _apply_sysctl
      log_ok "zram sysctl optimizations applied."
    fi
  else
    log_skip "${zram_sysctl} already exists."
  fi

  log_ok "zram configured."
  log_info "Check zram status with: zramctl"
}

# ── OOM killer ────────────────────────────────────────────────────────────────
_configure_oom_killer() {
  # earlyoom: not explicitly in aur-wiki-improving-performance.txt but is a
  # standard Arch package for preventing system freezes on OOM.
  # systemd-oomd: part of systemd, kills cgroups under memory pressure.
  echo ""
  echo "OOM (Out of Memory) killer configuration:"
  echo "  [1] earlyoom [★ recomendado] — kills processes before the system freezes (AUR)"
  echo "  [2] systemd-oomd             — built-in systemd OOM daemon, no extra packages"
  echo "  [3] Skip"
  echo ""
  log_info "Without an OOM killer, a system running out of memory can freeze for minutes."

  local oom_choice
  read -r -p "Choice [1]: " oom_choice

  case "${oom_choice:-1}" in
    1) _install_earlyoom    ;;
    2) _configure_systemd_oomd ;;
    3) log_skip "OOM killer configuration skipped." ;;
    *) log_warn "Invalid choice — skipping OOM killer configuration." ;;
  esac
}

_install_earlyoom() {
  aur_install earlyoom
  run_cmd sudo systemctl enable --now earlyoom.service
  log_ok "earlyoom installed and enabled."
  log_info "earlyoom will kill the largest memory consumers before the kernel OOM killer acts."
}

_configure_systemd_oomd() {
  local oomd_conf_dir="/etc/systemd/oomd.conf.d"
  local oomd_conf="${oomd_conf_dir}/archforge.conf"

  if [[ -f "${oomd_conf}" ]]; then
    log_skip "${oomd_conf} already exists."
  else
    backup_file "${oomd_conf}"
    local tmp
    tmp="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '${tmp}'" RETURN
    run_cmd sudo mkdir -p "${oomd_conf_dir}"
    cat > "${tmp}" <<'EOF'
# systemd-oomd configuration — archforge
# Kills cgroups when swap usage exceeds 80% or memory pressure is sustained.
[OOM]
SwapUsedLimit=80%
DefaultMemoryPressureLimit=60%
DefaultMemoryPressureDurationSec=20s
EOF
    run_cmd sudo cp "${tmp}" "${oomd_conf}"
  fi

  run_cmd sudo systemctl enable --now systemd-oomd.service
  log_ok "systemd-oomd enabled."
  log_info "Monitors memory pressure and kills cgroups exceeding thresholds."
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
