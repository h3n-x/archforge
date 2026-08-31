#!/usr/bin/env bash
# modules/12-peripherals/printing.sh
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

# Insert "mdns_minimal [NOTFOUND=return] " into the nsswitch.conf "hosts:"
# line, immediately before "resolve" if present — matching the exact
# ArchWiki example (aur-wiki-avahi.txt): "hosts: mymachines mdns_minimal
# [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns".
# Falls back to immediately before "dns" if "resolve" is absent, or appends
# to the end of the line if neither token is present. A plain greedy
# `s/\(hosts:.*\)\(resolve\|dns\)/.../ ` (the previous approach) inserts
# before the *last* match instead of "resolve", landing after it — wrong
# per the wiki and confirmed by testing against a real default nsswitch line.
_insert_mdns_minimal() {
  local file="$1"
  sed -E '/^hosts:/ {
    /\bresolve\b/ { s/\bresolve\b/mdns_minimal [NOTFOUND=return] resolve/; b }
    /\bdns\b/ { s/\bdns\b/mdns_minimal [NOTFOUND=return] dns/; b }
    s/$/ mdns_minimal [NOTFOUND=return]/
  }' "${file}"
}

module_info() {
  MODULE_NAME="Peripherals: Printing (CUPS)"
  MODULE_DESC="Install and configure CUPS, optional scanner support (SANE), printer driver packages"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES="cups cups-pdf"
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-CUPS.txt aur-wiki-CUPS-Troubleshooting.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info

  # Step 1: Install core CUPS
  pacman_install cups cups-pdf

  # Step 2: Enable CUPS service
  run_cmd sudo systemctl enable --now cups.service

  # Step 3: Optional Avahi for network printer discovery
  if confirm "Enable Avahi for automatic network printer discovery?" "y"; then
    pacman_install avahi nss-mdns
    run_cmd sudo systemctl enable --now avahi-daemon.service

    # Configure nsswitch.conf for mDNS resolution
    local nsswitch="/etc/nsswitch.conf"
    if grep -q 'mdns_minimal' "${nsswitch}" 2>/dev/null; then
      log_info "nsswitch.conf already contains mdns_minimal — skipping."
    else
      backup_file "${nsswitch}"
      local tmp
      tmp="$(mktemp)"
      # shellcheck disable=SC2064
      trap "rm -f '${tmp}'" RETURN
      _insert_mdns_minimal "${nsswitch}" > "${tmp}"
      run_cmd sudo cp "${tmp}" "${nsswitch}"
      log_ok "nsswitch.conf updated for mDNS"
    fi
  fi

  # Step 4: Optional SANE scanner support
  if confirm "Install SANE scanner support?" "y"; then
    pacman_install sane
    if confirm "Install simple-scan (GTK scanner frontend)?" "y"; then
      pacman_install simple-scan
    fi
  fi

  # Step 5: Optional printer driver groups
  >&2 echo ""
  >&2 echo "--- Optional printer drivers ---"
  >&2 echo "Select any drivers to install for your printer brand."
  >&2 echo ""

  if confirm "Install HP printer drivers (hplip)?" "y"; then
    pacman_install hplip
  fi

  if confirm "Install Epson printer drivers (epson-inkjet-printer-escpr, AUR)?" "y"; then
    aur_install epson-inkjet-printer-escpr
  fi

  if confirm "Install Brother printer drivers (brlaser, AUR)?" "y"; then
    aur_install brlaser
  fi

  if confirm "Install Canon printer drivers (cnijfilter2, AUR)?" "y"; then
    aur_install cnijfilter2
  fi

  if confirm "Install Samsung/Xerox drivers (splix, AUR)?" "y"; then
    aur_install splix
  fi

  # Step 6: Final summary
  log_ok "CUPS installed and enabled."
  log_info "Manage printers at: http://localhost:631"
  log_info "Or use system-config-printer for a GUI printer manager (pacman_install system-config-printer)."
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
