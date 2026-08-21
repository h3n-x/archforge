#!/usr/bin/env bash
# modules/03-security/antivirus.sh
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
  MODULE_NAME="Security: Antivirus (ClamAV)"
  MODULE_DESC="Install ClamAV, configure daemon, update signatures, optional on-access scanning"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES="clamav"
  MODULE_AUR_PACKAGES=""
  # Source: aur-wiki-clamav.txt
  MODULE_WIKI_SOURCE="aur-wiki-clamav.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info

  # Source: aur-wiki-clamav.txt — "Installation":
  # "Install the clamav package."
  pacman_install clamav

  # ── Signature update service ──────────────────────────────────────────────
  # Source: aur-wiki-clamav.txt — "Updating database":
  # "Start/enable clamav-freshclam.service so that the virus definitions are kept recent."
  # "The clamav-freshclam.service launches freshclam in daemon mode,
  #  defaulting to 12 checks per day (every 2 hours)."
  log_info "Enabling ClamAV signature update service (clamav-freshclam)..."
  local freshclam_active=false
  if [[ "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    if systemctl is-active --quiet clamav-freshclam.service 2>/dev/null; then
      freshclam_active=true
    fi
  fi
  if [[ "${freshclam_active}" == "true" ]]; then
    log_info "clamav-freshclam.service is active — restarting to trigger update..."
    run_cmd sudo systemctl restart clamav-freshclam.service
  else
    run_cmd sudo systemctl enable --now clamav-freshclam.service
  fi
  log_ok "clamav-freshclam.service enabled (signature updates every 2 hours)."

  # ── clamd configuration ───────────────────────────────────────────────────
  _configure_clamd

  # ── On-access real-time scanning ──────────────────────────────────────────
  _configure_on_access_scan

  # ── Weekly scheduled scan timer ───────────────────────────────────────────
  _configure_scan_timer

  log_ok "ClamAV configured."
}

# ── clamd configuration ───────────────────────────────────────────────────────
_configure_clamd() {
  # Source: aur-wiki-clamav.txt — "Configuration":
  # "Additional recommended configurations can be set" in /etc/clamav/clamd.conf:
  # LogTime yes, ExtendedDetectionInfo yes, User clamav, MaxDirectoryRecursion 20,
  # DetectPUA yes, HeuristicAlerts yes, ScanPE/ELF/OLE2/PDF/HTML/Archive yes,
  # AlertBrokenExecutables yes, AlertEncrypted yes, AlertOLE2Macros yes.
  local clamd_conf="/etc/clamav/clamd.conf"

  if [[ ! -f "${clamd_conf}" ]]; then
    log_warn "clamd.conf not found — skipping daemon configuration."
    return 0
  fi

  log_info "Applying recommended clamd.conf settings (detection, logging, scan types)."

  backup_file "${clamd_conf}"
  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp}'" RETURN
  cp "${clamd_conf}" "${tmp}"

  _set_clamav_option "${tmp}" "LogTime"               "yes"
  _set_clamav_option "${tmp}" "ExtendedDetectionInfo" "yes"
  _set_clamav_option "${tmp}" "User"                  "clamav"
  _set_clamav_option "${tmp}" "MaxDirectoryRecursion" "20"
  _set_clamav_option "${tmp}" "DetectPUA"             "yes"
  _set_clamav_option "${tmp}" "HeuristicAlerts"       "yes"
  _set_clamav_option "${tmp}" "ScanPE"                "yes"
  _set_clamav_option "${tmp}" "ScanELF"               "yes"
  _set_clamav_option "${tmp}" "ScanOLE2"              "yes"
  _set_clamav_option "${tmp}" "ScanPDF"               "yes"
  _set_clamav_option "${tmp}" "ScanHTML"              "yes"
  _set_clamav_option "${tmp}" "ScanArchive"           "yes"
  _set_clamav_option "${tmp}" "AlertBrokenExecutables" "yes"
  _set_clamav_option "${tmp}" "AlertEncrypted"        "yes"
  _set_clamav_option "${tmp}" "AlertOLE2Macros"       "yes"

  run_cmd sudo cp "${tmp}" "${clamd_conf}"
  log_ok "clamd.conf updated with recommended detection settings."
}

# ── On-access real-time scanning ──────────────────────────────────────────────
_configure_on_access_scan() {
  # Source: aur-wiki-clamav.txt — "Enabling real-time protection OnAccessScan":
  # "On-access scanning is the real-time protection daemon which will scan the
  #  file while reading, writing or executing it."
  # "The following changes are required for OnAccessScan to work:
  #   OnAccessExcludeUname clamav  (prevent scan loops)"
  # "The following additional changes are recommended (notify-only mode):
  #   OnAccessMountPath /
  #   OnAccessPrevention no
  #   OnAccessExtraScanning yes"
  # Source: aur-wiki-clamav.txt — "Starting the ClamAV + OnAccessScanning daemon":
  # "As of February 2024 these signatures require at least 1.6 GiB of free RAM."
  # "You will need to run freshclam before starting the service for the first time."

  log_info "On-access scanning provides real-time file monitoring (requires clamd daemon)."
  log_info "Note: requires at least 1.6 GiB free RAM (wiki: aur-wiki-clamav.txt)."

  if ! confirm "Enable clamd + on-access scanning (real-time protection)?" "n"; then
    return 0
  fi

  local clamd_conf="/etc/clamav/clamd.conf"
  if [[ ! -f "${clamd_conf}" ]]; then
    log_warn "clamd.conf not found — skipping on-access configuration."
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp}'" RETURN
  cp "${clamd_conf}" "${tmp}"

  # Required: exclude clamav user UID to prevent scan loops
  _set_clamav_option "${tmp}" "OnAccessExcludeUname"  "clamav"
  # Recommended notify-only settings
  _set_clamav_option "${tmp}" "OnAccessMountPath"     "/"
  _set_clamav_option "${tmp}" "OnAccessPrevention"    "no"
  _set_clamav_option "${tmp}" "OnAccessExtraScanning" "yes"

  run_cmd sudo cp "${tmp}" "${clamd_conf}"

  # Source: aur-wiki-clamav.txt — "The service is called clamav-daemon.service.
  #  Start it and enable it to start at boot."
  # "Additionally start and enable clamav-clamonacc.service for real-time on access protection."
  if [[ "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    run_cmd sudo systemctl enable --now clamav-daemon.service
    run_cmd sudo systemctl enable --now clamav-clamonacc.service
  fi
  log_ok "On-access scanning enabled (clamav-daemon + clamav-clamonacc)."
  log_info "View on-access log: journalctl -u clamav-clamonacc.service"
}

# ── Weekly scheduled scan timer ───────────────────────────────────────────────
_configure_scan_timer() {
  # Source: aur-wiki-clamav.txt — "Scan for viruses" / "using the stand-alone scanner":
  # "clamscan can be used to scan certain files, home directories, or an entire system:
  #  clamscan --recursive --infected /home/$USER"
  if ! confirm "Create weekly home directory scan timer?" "y"; then
    return 0
  fi

  local service_file="/etc/systemd/system/clamav-home-scan.service"
  local timer_file="/etc/systemd/system/clamav-home-scan.timer"

  local tmp_svc tmp_timer
  tmp_svc="$(mktemp)"
  tmp_timer="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp_svc}' '${tmp_timer}'" RETURN

  cat > "${tmp_svc}" << 'CLAMAV_SVC_EOF'
[Unit]
Description=Weekly ClamAV scan of home directory

[Service]
Type=oneshot
ExecStart=/usr/bin/clamscan -r --infected --log=/var/log/clamav/home-scan.log /home
CLAMAV_SVC_EOF

  cat > "${tmp_timer}" << 'CLAMAV_TIMER_EOF'
[Unit]
Description=Weekly ClamAV home scan

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
CLAMAV_TIMER_EOF

  run_cmd sudo cp "${tmp_svc}"   "${service_file}"
  run_cmd sudo cp "${tmp_timer}" "${timer_file}"
  run_cmd sudo chmod 644 "${service_file}" "${timer_file}"
  run_cmd sudo systemctl enable --now clamav-home-scan.timer
  log_ok "Weekly ClamAV home scan timer enabled."
  log_info "View scan results: cat /var/log/clamav/home-scan.log"
}

# Set or update a ClamAV config option (space-separated key value format).
# Handles commented entries (# Key value or #Key value) and absent entries.
_set_clamav_option() {
  local file="$1" key="$2" value="$3"
  local ek ev
  ek="$(printf '%s' "${key}"   | sed 's/[]\\/$*.^[]/\\&/g')"
  ev="$(printf '%s' "${value}" | sed 's/[\\/&]/\\&/g')"

  if grep -q "^${ek} " "${file}" 2>/dev/null; then
    # Active entry — update in place
    sed -i "s/^${ek} .*/${ek} ${ev}/" "${file}"
  elif grep -q "^# ${ek} " "${file}" 2>/dev/null; then
    # Comment with space: "# Key value" — uncomment and update
    sed -i "s/^# ${ek} .*/${ek} ${ev}/" "${file}"
  elif grep -q "^#${ek} " "${file}" 2>/dev/null; then
    # Comment without space: "#Key value" — uncomment and update
    sed -i "s/^#${ek} .*/${ek} ${ev}/" "${file}"
  else
    # Not found — append
    printf '%s %s\n' "${key}" "${value}" >> "${file}"
  fi
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
