#!/usr/bin/env bash
# modules/05-networking/network.sh
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

# Update the 3 standard entries in /etc/hosts (127.0.0.1, ::1, 127.0.1.1)
# in place, preserving every other line untouched — VPN hosts, docker
# entries, ad-block lists, or anything else the user or other tools have
# added. Idempotent: replaces the existing line for each address if
# present, appends it if absent. Previously this fully overwrote
# /etc/hosts with only these 3 lines, discarding any custom entries.
_update_hosts_file() {
  local file="$1" hostname="$2"
  local src="/dev/null"
  [[ -f "${file}" ]] && src="${file}"
  awk -v host="${hostname}" '
    BEGIN {
      seen_loopback4 = 0
      seen_loopback6 = 0
      seen_hostname  = 0
    }
    /^127\.0\.0\.1[[:space:]]/ {
      print "127.0.0.1   localhost"
      seen_loopback4 = 1
      next
    }
    /^::1[[:space:]]/ {
      print "::1         localhost"
      seen_loopback6 = 1
      next
    }
    /^127\.0\.1\.1[[:space:]]/ {
      print "127.0.1.1   " host ".localdomain " host
      seen_hostname = 1
      next
    }
    { print }
    END {
      if (!seen_loopback4) print "127.0.0.1   localhost"
      if (!seen_loopback6) print "::1         localhost"
      if (!seen_hostname)  print "127.0.1.1   " host ".localdomain " host
    }
  ' "${src}"
}

module_info() {
  MODULE_NAME="Networking: network configuration"
  MODULE_DESC="Set hostname, configure /etc/hosts, verify NetworkManager, WiFi power save, regulatory domain, MAC randomization"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES=""
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-network-configuration.txt aur-wiki-networkmanager.txt aur-wiki-wireless.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info

  local current_hostname
  current_hostname="$(hostnamectl hostname 2>/dev/null || hostnamectl --static 2>/dev/null || hostname)"
  log_info "Current hostname: ${current_hostname}"
  if [[ ${#current_hostname} -le 1 ]] || \
     [[ ! "${current_hostname}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
    log_warn "Current hostname '${current_hostname}' appears invalid — a new hostname is recommended"
  fi

  local new_hostname
  read -r -p "New hostname (blank to keep '${current_hostname}'): " new_hostname
  if [[ -n "${new_hostname}" && "${new_hostname}" != "${current_hostname}" ]]; then
    run_cmd sudo hostnamectl set-hostname "${new_hostname}"
    current_hostname="${new_hostname}"
  fi

  # /etc/hosts — update the 3 standard entries in place, preserving any
  # custom entries already in the file (see _update_hosts_file above).
  backup_file "/etc/hosts"
  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp}'" RETURN
  _update_hosts_file "/etc/hosts" "${current_hostname}" > "${tmp}"
  diff /etc/hosts "${tmp}" || true
  if confirm "Apply /etc/hosts changes?" "y"; then
    run_cmd sudo cp "${tmp}" /etc/hosts
  fi

  if ! systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
    if confirm "Enable NetworkManager?" "y"; then
      run_cmd sudo systemctl enable --now NetworkManager
    fi
  fi

  # ── WiFi power save ───────────────────────────────────────────────────────
  _configure_wifi_powersave

  # ── Wireless regulatory domain ────────────────────────────────────────────
  _configure_regulatory_domain

  # ── MAC address randomization ─────────────────────────────────────────────
  _configure_mac_randomization

  log_ok "Network configured."
}

# ── WiFi power save ───────────────────────────────────────────────────────────
_configure_wifi_powersave() {
  # Source: aur-wiki-wireless.txt — "Random disconnections" / Cause #7:
  # "the disconnection may be due to power saving, which will block incoming
  #  traffic and prevent connections. Try disabling power saving for the interface:
  #  iw dev interface set power_save off"
  # Configured here via NetworkManager conf.d so it persists across reboots
  # and applies to all managed wireless interfaces.
  local powersave_conf="/etc/NetworkManager/conf.d/wifi-powersave.conf"

  if [[ -f "${powersave_conf}" ]]; then
    log_skip "${powersave_conf} already exists."
    return 0
  fi

  log_info "WiFi power save can cause random disconnects on some cards (deauth reason=3)."
  log_info "Disabling it improves stability, at a small battery cost."

  if confirm "Disable WiFi power save (recommended for desktops, optional for laptops)?" "y"; then
    backup_file "${powersave_conf}"
    local tmp_ps
    tmp_ps="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '${tmp_ps}'" RETURN
    cat > "${tmp_ps}" <<'EOF'
# WiFi power save configuration
# Source: aur-wiki-wireless.txt — "Random disconnections" Cause #7
# wifi.powersave = 2: disable power save (iw dev interface set power_save off equivalent)
# wifi.powersave = 3: enable power save
[connection]
wifi.powersave = 2
EOF
    run_cmd sudo install -Dm644 "${tmp_ps}" "${powersave_conf}"
    run_cmd sudo systemctl reload NetworkManager
    log_ok "WiFi power save disabled (${powersave_conf})."
    log_info "Reload takes effect for new connections — reconnect WiFi to apply."
  fi
}

# ── Wireless regulatory domain ────────────────────────────────────────────────
_configure_regulatory_domain() {
  # Source: aur-wiki-wireless.txt — "Respecting the regulatory domain" (lines 311-348):
  # "To configure the regdomain, install wireless-regdb and reboot, then edit
  #  /etc/conf.d/wireless-regdom and uncomment the appropriate domain."
  # Source: aur-wiki-networkmanager.txt — "Unable to connect to visible European wireless networks":
  # "Install wireless-regdb. Uncomment the correct country code in /etc/conf.d/wireless-regdom."
  local regdom_conf="/etc/conf.d/wireless-regdom"

  log_info "Wireless regulatory domain controls available channels and transmit power."
  log_info "Misconfiguration may hide networks or limit performance."

  local current_reg
  current_reg="$(iw reg get 2>/dev/null | awk '/^country/{print $2; exit}' | tr -d ':' || echo 'unknown')"
  log_info "Current regulatory domain: ${current_reg}"

  if ! confirm "Configure wireless regulatory domain?" "y"; then
    return 0
  fi

  # Source: aur-wiki-wireless.txt — "The kernel loads the database directly when
  # wireless-regdb is installed."
  pacman_install wireless-regdb

  if [[ ! -f "${regdom_conf}" ]]; then
    log_warn "${regdom_conf} not found — wireless-regdb may not be installed correctly."
    return 1
  fi

  log_info "Enter your ISO 3166-1 alpha-2 country code (e.g. US, ES, DE, FR, GB, JP, CN)."
  log_info "See: https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2"
  local country_code
  while true; do
    read -r -p "Country code: " country_code
    country_code="${country_code^^}"  # uppercase
    if [[ "${country_code}" =~ ^[A-Z]{2}$ ]]; then
      break
    fi
    log_warn "Invalid country code '${country_code}' — must be exactly 2 letters (e.g. US, DE)."
  done

  backup_file "${regdom_conf}"

  # Comment out any currently active WIRELESS_REGDOM entries, then activate the new one.
  # Source: aur-wiki-wireless.txt — "edit /etc/conf.d/wireless-regdom and uncomment the appropriate domain"
  local tmp_reg
  tmp_reg="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp_reg}'" RETURN

  # Disable any currently active regdom lines, then activate (or append) the user's choice.
  sed 's/^WIRELESS_REGDOM=/#WIRELESS_REGDOM=/' "${regdom_conf}" > "${tmp_reg}"

  if grep -q "^#WIRELESS_REGDOM=\"${country_code}\"" "${tmp_reg}"; then
    # Entry exists (commented) — uncomment it
    sed -i "s/^#WIRELESS_REGDOM=\"${country_code}\"/WIRELESS_REGDOM=\"${country_code}\"/" "${tmp_reg}"
  else
    # Entry not found — append it
    printf '\nWIRELESS_REGDOM="%s"\n' "${country_code}" >> "${tmp_reg}"
  fi

  run_cmd sudo cp "${tmp_reg}" "${regdom_conf}"
  log_ok "Regulatory domain set to '${country_code}' in ${regdom_conf}."

  # Apply immediately without reboot
  # Source: aur-wiki-wireless.txt — "The current regdomain can be temporarily set with: iw reg set"
  if [[ "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    run_cmd sudo iw reg set "${country_code}" || true
    log_info "Applied immediately via 'iw reg set ${country_code}' (persisted via ${regdom_conf})."
    log_info "Verify with: iw reg get"
    log_info "Note: a reboot is required for the kernel to fully load the new regdomain from wireless-regdb."
  fi
}

# ── MAC address randomization ─────────────────────────────────────────────────
_configure_mac_randomization() {
  # Source: aur-wiki-networkmanager.txt — "MAC address randomization":
  # "MAC randomization can be used for increased privacy by not disclosing your
  #  real MAC address to the network."
  # "You can configure the MAC randomization by adding the desired configuration
  #  under /etc/NetworkManager/conf.d"
  local mac_conf="/etc/NetworkManager/conf.d/mac-randomization.conf"

  if [[ -f "${mac_conf}" ]]; then
    log_skip "${mac_conf} already exists."
    return 0
  fi

  log_info "MAC randomization hides your real hardware MAC address from networks."

  # Show current MAC addresses before asking — user can see what they're hiding.
  # Source: aur-wiki-networkmanager.txt — NetworkManager devices
  log_info "Current device MAC addresses:"
  nmcli -f GENERAL.HWADDR device show 2>/dev/null | head -5 || true
  echo ""

  if ! confirm "Configure MAC address randomization?" "y"; then
    return 0
  fi

  # Source: aur-wiki-networkmanager.txt — "MAC address randomization":
  # "stable generates a random MAC address when you connect to a new network
  #  and associates the two permanently."
  # "random will generate a new MAC address every time you connect to a network"
  echo ""
  echo "MAC randomization modes:"
  echo "  [1] stable [★ recomendado] — one random MAC per network, remembered across connections"
  echo "  [2] random                 — new random MAC on every connection (maximum privacy)"
  echo ""

  local mode_choice wifi_mode eth_mode
  read -r -p "Mode [1]: " mode_choice
  case "${mode_choice:-1}" in
    2)
      wifi_mode="random"
      eth_mode="random"
      ;;
    *)
      wifi_mode="stable"
      eth_mode="random"
      ;;
  esac

  log_info "WiFi: cloned-mac-address=${wifi_mode} / Ethernet: cloned-mac-address=${eth_mode}"

  # Source: aur-wiki-networkmanager.txt — note about MAC randomization:
  # "Disabling MAC address randomization may be needed to get (stable) link
  #  connection and/or networks that restrict devices based on their MAC Address"
  log_warn "Some networks (e.g. captive portals, MAC-filtered networks) may reject randomized MACs."
  log_warn "If a network stops working, set its connection's cloned-mac-address to 'preserve' or 'permanent'."

  backup_file "${mac_conf}"
  local tmp_mac
  tmp_mac="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp_mac}'" RETURN
  cat > "${tmp_mac}" <<EOF
# MAC address randomization
# Source: aur-wiki-networkmanager.txt — "MAC address randomization"
# Modes: stable (same MAC per network), random (new MAC each connection),
#        preserve (keep current), permanent (use hardware MAC)

[device-mac-randomization]
# Randomize MAC during Wi-Fi scanning (default: yes)
wifi.scan-rand-mac-address=yes

[connection-mac-randomization]
# Wi-Fi: ${wifi_mode} — ${wifi_mode} MAC per network
wifi.cloned-mac-address=${wifi_mode}
# Ethernet: ${eth_mode} MAC per connection
ethernet.cloned-mac-address=${eth_mode}
EOF
  run_cmd sudo install -Dm644 "${tmp_mac}" "${mac_conf}"
  run_cmd sudo systemctl reload NetworkManager
  log_ok "MAC randomization configured (${mac_conf})."
  log_info "Changes apply to new connections — reconnect to activate."
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
