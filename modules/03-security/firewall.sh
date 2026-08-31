#!/usr/bin/env bash
# modules/03-security/firewall.sh
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
  MODULE_NAME="Security: Firewall (nftables)"
  MODULE_DESC="Configure nftables firewall with desktop/server/strict profile"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES="nftables"
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-nftables.txt aur-wiki-iptables.txt aur-wiki-simple-stateful-firewall.txt"
  MODULE_DEPENDS=""
}

module_run() {
  pacman_install nftables

  local profile
  profile="$(_select_firewall_profile)"
  [[ -z "${profile}" ]] && return 2

  backup_file "/etc/nftables.conf"

  # shellcheck disable=SC2154
  local config_src="${ARCHFORGE_DIR}/configs/nftables-${profile}.conf"

  # Defense-in-depth: confirm path stays within expected directory
  local resolved_src
  resolved_src="$(realpath -m "${config_src}")"
  if [[ "${resolved_src}" != "${ARCHFORGE_DIR}/configs/"* ]]; then
    log_error "Config path escapes expected directory — aborting"
    return 1
  fi

  if [[ ! -f "${config_src}" ]]; then
    log_error "Config template not found: ${config_src}"
    return 1
  fi

  run_cmd sudo cp "${config_src}" /etc/nftables.conf
  run_cmd sudo systemctl enable --now nftables
  log_ok "Firewall enabled: ${profile} profile"

  # ── Firewall log viewer ────────────────────────────────────────────────────
  # Source: aur-wiki-nftables.txt — "Logging traffic":
  # "You can log packets using the log action."
  # Drop packets are logged with prefix "nftables-drop: " — viewable via journalctl.
  log_info "Dropped packets are logged with prefix 'nftables-drop:'"
  log_info "View firewall drop log: journalctl -k --grep=\"nftables-drop\" --since=\"1 hour ago\""
  if confirm "Show firewall drop log now?" "n"; then
    journalctl -k --grep="nftables-drop" --since="1 hour ago" || true
  fi
  return 0
}

_select_firewall_profile() {
  # In non-interactive modes, default to desktop (safe, non-destructive)
  if [[ "${YES_FLAG:-false}" == "true" || "${DRY_RUN:-false}" == "true" ]]; then
    echo "desktop"
    return 0
  fi

  echo "" >&2
  echo "Select firewall profile:" >&2
  echo "  [1] desktop [★ recomendado] — allow all outbound, block unsolicited inbound" >&2
  echo "  [2] server                  — desktop + configurable open ports (22, 80, 443)" >&2
  echo "  [3] strict                  — drop ALL traffic, manual whitelist required" >&2
  echo "  [q] Cancel" >&2
  local choice
  read -r -p "Profile: " choice
  case "${choice}" in
    1) echo "desktop" ;;
    2) echo "server"  ;;
    3)
      log_warn "Strict profile will drop ALL outbound traffic."
      log_warn "You MUST add rules manually or you will lose connectivity!"
      confirm "Understood — apply strict profile?" || { echo ""; return 0; }
      echo "strict"
      ;;
    q) echo "" ;;
    *) echo "" ;;
  esac
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
