#!/usr/bin/env bash
# modules/04-power/acpid.sh
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
  MODULE_NAME="Power: ACPI events (acpid)"
  MODULE_DESC="Handle lid close (suspend) and power button events"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN="Designed for laptops — not recommended on desktop"
  MODULE_PACKAGES="acpid"
  MODULE_AUR_PACKAGES=""
  MODULE_WIKI_SOURCE="aur-wiki-acpid.txt aur-wiki-power-managements.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info
  set +T 2>/dev/null || true

  if [[ "${SYSTEM_TYPE:-desktop}" == "desktop" ]]; then
    log_warn "⚠ ${MODULE_HW_WARN}"
    confirm "Apply acpid on desktop anyway?" || return 2
  fi

  pacman_install acpid
  run_cmd sudo systemctl enable --now acpid

  # Lid close → suspend
  # ArchWiki: https://wiki.archlinux.org/title/Acpid
  # To avoid conflicting suspend actions between systemd-logind and acpid,
  # systemd-logind should be configured to ignore lid switch events.
  if confirm "Configure lid close to suspend?"; then
    run_cmd sudo mkdir -p /etc/acpi/events
    # Write lid event handler
    local lid_event lid_action
    lid_event="$(mktemp)"
    lid_action="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '${lid_event}' '${lid_action}'" RETURN

    cat > "${lid_event}" <<'EOF'
event=button/lid.*
action=/etc/acpi/archforge-lid.sh
EOF
    cat > "${lid_action}" <<'EOF'
#!/bin/bash
grep -q open /proc/acpi/button/lid/*/state && exit 0
systemctl suspend
EOF
    backup_file "/etc/acpi/events/archforge-lid"
    backup_file "/etc/acpi/archforge-lid.sh"
    run_cmd sudo cp "${lid_event}" /etc/acpi/events/archforge-lid
    run_cmd sudo cp "${lid_action}" /etc/acpi/archforge-lid.sh
    run_cmd sudo chmod +x /etc/acpi/archforge-lid.sh

    # Prevent conflict with systemd-logind (ArchWiki: Acpid)
    local logind_dropin="/etc/systemd/logind.conf.d/archforge-acpid.conf"
    backup_file "${logind_dropin}"
    local logind_tmp
    logind_tmp="$(mktemp)"
    cat > "${logind_tmp}" <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
    run_cmd sudo mkdir -p /etc/systemd/logind.conf.d
    run_cmd sudo install -Dm644 "${logind_tmp}" "${logind_dropin}"
    rm -f "${logind_tmp}"
    log_info "Configured systemd-logind to ignore lid switch to prevent conflict with acpid."
  fi

  log_ok "acpid configured."
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
