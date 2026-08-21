#!/usr/bin/env bash
# modules/03-security/dns.sh
# shellcheck shell=bash
set -euo pipefail

# shellcheck source=../../lib/core.sh
# shellcheck disable=SC2154,SC1091
source "${ARCHFORGE_DIR}/lib/core.sh"
# shellcheck source=../../lib/backup.sh
# shellcheck disable=SC1091
source "${ARCHFORGE_DIR}/lib/backup.sh"

module_info() {
  MODULE_NAME="Security: DNS configuration"
  MODULE_DESC="Configure DNS provider (Quad9/Cloudflare/AdGuard) via resolved or NetworkManager"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES=""
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-domain-name-resolution.txt aur-wiki-dnssec.txt"
  MODULE_DEPENDS="network"
}

module_run() {
  module_info

  local provider
  provider="$(_select_dns_provider)"
  [[ -z "${provider}" ]] && return 2

  _build_dns_config "${provider}"

  # Detect active DNS infrastructure — guarded for test environments
  local has_resolved=false has_nm=false
  if [[ "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then has_resolved=true; fi
    if systemctl is-active --quiet NetworkManager  2>/dev/null; then has_nm=true; fi
  fi

  if [[ "${has_resolved}" == "true" && "${has_nm}" == "true" ]]; then
    _configure_resolved_with_nm
  elif [[ "${has_resolved}" == "true" ]]; then
    _configure_resolved_only
  elif [[ "${has_nm}" == "true" ]]; then
    _configure_nm_only
  else
    _configure_resolv_conf_direct
  fi

  log_ok "DNS configured: ${provider}"
}

_select_dns_provider() {
  if [[ "${YES_FLAG:-false}" == "true" ]]; then
    echo "quad9"
    return 0
  fi
  # All display output goes to stderr so command substitution captures only the provider name
  echo "" >&2
  echo "Select DNS provider:" >&2
  echo "  [1] Quad9          [★ recommended] — malware blocking + DNSSEC enforced" >&2
  echo "  [2] Quad9 + ECS    [★ recommended] — malware blocking + DNSSEC enforced + ECS" >&2
  echo "  [3] Cloudflare 1.1.1.1             — speed, no blocking, DNSSEC: allow-downgrade" >&2
  echo "  [4] Cloudflare 1.1.1.2             — malware blocking, DNSSEC: allow-downgrade" >&2
  echo "  [5] AdGuard                        — ads + malware blocking, DNSSEC: allow-downgrade" >&2
  echo "  [6] Custom                         — enter IPs manually" >&2
  echo "  [q] Cancel" >&2
  local choice
  read -r -p "Choice: " choice
  case "${choice}" in
    1) echo "quad9"              ;;
    2) echo "quad9-ecs"          ;;
    3)
      log_warn "Cloudflare 1.1.1.1: no malware/ad blocking; DNSSEC not enforced (allow-downgrade)."
      confirm "Proceed with Cloudflare 1.1.1.1?" "y" || { echo ""; return 0; }
      echo "cloudflare"
      ;;
    4) echo "cloudflare-malware" ;;
    5)
      log_warn "AdGuard: DNSSEC not enforced (allow-downgrade). Filtering relies on AdGuard's own blocklists."
      confirm "Proceed with AdGuard?" "y" || { echo ""; return 0; }
      echo "adguard"
      ;;
    6) echo "custom"             ;;
    *) echo ""                   ;;
  esac
}

_build_dns_config() {
  local provider="$1"
  DNS_PRIMARY="" DNS_PRIMARY6="" DNS_FALLBACK="" DNS_FALLBACK6=""
  DNS_DNSSEC="" DNS_DOT=""

  case "${provider}" in
    quad9)
      DNS_PRIMARY="9.9.9.9 149.112.112.112"
      DNS_PRIMARY6="2620:fe::fe 2620:fe::9"
      DNS_FALLBACK="9.9.9.10 149.112.112.10"
      DNS_FALLBACK6="2620:fe::fe:10 2620:fe::10"
      DNS_DNSSEC="yes"
      DNS_DOT="opportunistic"
      ;;
    quad9-ecs)
      DNS_PRIMARY="9.9.9.11 149.112.112.11"
      DNS_PRIMARY6="2620:fe::11 2620:fe::fe:11"
      DNS_FALLBACK="9.9.9.10 149.112.112.10"
      DNS_FALLBACK6="2620:fe::10 2620:fe::fe:10"
      DNS_DNSSEC="yes"
      DNS_DOT="opportunistic"
      ;;
    cloudflare)
      DNS_PRIMARY="1.1.1.1 1.0.0.1"
      DNS_PRIMARY6="2606:4700:4700::1111 2606:4700:4700::1001"
      DNS_FALLBACK=""
      DNS_FALLBACK6=""
      DNS_DNSSEC="allow-downgrade"
      DNS_DOT="opportunistic"
      ;;
    cloudflare-malware)
      DNS_PRIMARY="1.1.1.2 1.0.0.2"
      DNS_PRIMARY6="2606:4700:4700::1112 2606:4700:4700::1002"
      DNS_FALLBACK=""
      DNS_FALLBACK6=""
      DNS_DNSSEC="allow-downgrade"
      DNS_DOT="opportunistic"
      ;;
    adguard)
      DNS_PRIMARY="94.140.14.14 94.140.15.15"
      DNS_PRIMARY6="2a10:50c0::ad1:ff 2a10:50c0::ad2:ff"
      DNS_FALLBACK=""
      DNS_FALLBACK6=""
      DNS_DNSSEC="allow-downgrade"
      DNS_DOT="opportunistic"
      ;;
    custom)
      read -r -p "IPv4 DNS (space-separated): "           DNS_PRIMARY
      read -r -p "IPv6 DNS (space-separated, or blank): " DNS_PRIMARY6
      DNS_FALLBACK="" DNS_FALLBACK6=""
      DNS_DNSSEC="allow-downgrade"
      DNS_DOT="no"
      ;;
    *)
      log_error "Unknown DNS provider: ${provider}"
      return 1
      ;;
  esac
  export DNS_PRIMARY DNS_PRIMARY6 DNS_FALLBACK DNS_FALLBACK6 DNS_DNSSEC DNS_DOT
}

# ── Configuration backends ────────────────────────────────────────────────────

_clear_immutable_if_set() {
  local path="$1"
  if [[ "${ARCHFORGE_TEST:-false}" == "true" ]]; then return 0; fi
  local attrs=""
  attrs="$(lsattr "${path}" 2>/dev/null || true)"
  # shellcheck disable=SC2312
  if [[ -e "${path}" ]] && echo "${attrs}" | awk '{print $1}' | grep -q 'i'; then
    log_warn "${path} has immutable flag — removing to allow reconfiguration"
    run_cmd sudo chattr -i "${path}"
  fi
}

_write_resolved_conf() {
  backup_file "/etc/systemd/resolved.conf"
  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp}'" RETURN

  local fallback_line=""
  if [[ -n "${DNS_FALLBACK}" || -n "${DNS_FALLBACK6}" ]]; then
    fallback_line="FallbackDNS=${DNS_FALLBACK} ${DNS_FALLBACK6}"
  fi

  {
    echo "[Resolve]"
    echo "DNS=${DNS_PRIMARY} ${DNS_PRIMARY6}"
    [[ -n "${fallback_line}" ]] && echo "${fallback_line}"
    echo "DNSSEC=${DNS_DNSSEC}"
    echo "DNSOverTLS=${DNS_DOT}"
  } > "${tmp}"

  run_cmd sudo cp "${tmp}" /etc/systemd/resolved.conf
}

_configure_resolved_only() {
  log_info "Configuring systemd-resolved (standalone)"
  _write_resolved_conf
  # /etc/resolv.conf may be a symlink — backup_file handles symlinks correctly
  backup_file "/etc/resolv.conf"
  _clear_immutable_if_set "/etc/resolv.conf"
  run_cmd sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  run_cmd sudo systemctl restart systemd-resolved
}

_configure_resolved_with_nm() {
  log_info "Configuring systemd-resolved + NetworkManager integration"
  _write_resolved_conf

  local nm_conf="/etc/NetworkManager/conf.d/archforge-dns.conf"
  backup_file "${nm_conf}"
  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp}'" RETURN
  printf '[main]\ndns=systemd-resolved\n' > "${tmp}"
  run_cmd sudo cp "${tmp}" "${nm_conf}"

  backup_file "/etc/resolv.conf"
  _clear_immutable_if_set "/etc/resolv.conf"
  run_cmd sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  run_cmd sudo systemctl restart systemd-resolved
  run_cmd sudo systemctl restart NetworkManager
}

_configure_nm_only() {
  log_info "Configuring DNS via NetworkManager (no systemd-resolved)"
  local conn=""
  if [[ "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    conn="$(nmcli -t -f NAME con show --active 2>/dev/null | head -1 || true)"
  fi
  if [[ -z "${conn}" ]]; then
    log_error "No active NetworkManager connection found."
    return 1
  fi
  run_cmd sudo nmcli con mod "${conn}" ipv4.dns              "${DNS_PRIMARY}"
  run_cmd sudo nmcli con mod "${conn}" ipv4.ignore-auto-dns  yes
  if [[ -n "${DNS_PRIMARY6}" ]]; then
    run_cmd sudo nmcli con mod "${conn}" ipv6.dns             "${DNS_PRIMARY6}"
    run_cmd sudo nmcli con mod "${conn}" ipv6.ignore-auto-dns yes
  fi
  run_cmd sudo nmcli con up  "${conn}"
}

_configure_resolv_conf_direct() {
  log_warn "No systemd-resolved or NetworkManager detected."
  log_warn "Writing /etc/resolv.conf directly."
  log_warn "Your network manager may overwrite this on reconnect."
  backup_file "/etc/resolv.conf"
  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp}'" RETURN
  {
    echo "# Generated by archforge"
    local ip
    # shellcheck disable=SC2086
    for ip in ${DNS_PRIMARY} ${DNS_PRIMARY6}; do
      [[ -n "${ip}" ]] && echo "nameserver ${ip}"
    done
  } > "${tmp}"
  run_cmd sudo cp "${tmp}" /etc/resolv.conf
  if confirm "Set immutable flag on /etc/resolv.conf (chattr +i) to prevent overwrite?"; then
    record_attr "/etc/resolv.conf"
    run_cmd sudo chattr +i /etc/resolv.conf
  fi
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
