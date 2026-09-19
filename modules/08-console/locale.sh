#!/usr/bin/env bash
# modules/08-console/locale.sh
# shellcheck shell=bash
set -euo pipefail

# shellcheck disable=SC2154,SC1091
source "${ARCHFORGE_DIR}/lib/core.sh"
# shellcheck disable=SC1091
source "${ARCHFORGE_DIR}/lib/backup.sh"

module_info() {
  MODULE_NAME="Console: Locale & timezone"
  MODULE_DESC="Set locale, timezone, NTP, and hardware clock UTC standard"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES=""
  MODULE_AUR_PACKAGES=""
  # Source: aur-wiki-locale.txt, aur-wiki-system-time.txt
  MODULE_WIKI_SOURCE="aur-wiki-locale.txt aur-wiki-system-time.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info

  # ── Locale ────────────────────────────────────────────────────────────────
  _configure_locale

  # ── Timezone & NTP ────────────────────────────────────────────────────────
  _configure_timezone

  # ── Hardware clock ────────────────────────────────────────────────────────
  _configure_hardware_clock

  log_ok "Locale and timezone configured."
}

# ── Locale ────────────────────────────────────────────────────────────────────
_configure_locale() {
  # Source: aur-wiki-locale.txt — "Generating locales":
  # "This can be achieved by uncommenting applicable entries in /etc/locale.gen,
  #  and running locale-gen."
  # "in addition to en_US.UTF-8 UTF-8 which is commonly used as a fallback for various tools"

  local current_locale
  current_locale="$(locale 2>/dev/null | awk -F= '/^LANG=/{gsub(/"/, "", $2); print $2}' || true)"
  if [[ ! "${current_locale}" =~ ^[a-zA-Z_]+\.UTF-8$ ]]; then
    current_locale="en_US.UTF-8"
  fi
  log_info "Current locale: ${current_locale}"

  # Drain any buffered stdin left over from previous prompts (terminal only)
  if [[ -t 0 ]]; then
    read -r -t 0.1 -n 10000 _ 2>/dev/null || true
  fi

  local locale="${current_locale}"
  if [[ "${YES_FLAG:-false}" == "true" && -t 0 ]]; then
    locale="${current_locale:-en_US.UTF-8}"
  else
    while true; do
      read -r -p "Locale to generate [${current_locale}]: " locale || true
      locale="${locale:-${current_locale}}"
      if [[ -z "${locale}" ]]; then
        log_skip "Locale generation skipped."
        return 0
      fi
      if [[ "${locale}" =~ ^[a-zA-Z_]+\.UTF-8$ ]]; then
        break
      fi
      log_error "Invalid locale format '${locale}'. Expected: language_TERRITORY.UTF-8 (e.g. en_US.UTF-8)"
      if [[ ! -t 0 ]]; then
        return 1
      fi
    done
  fi

  local tmp_gen tmp_conf
  tmp_gen="$(mktemp)"
  tmp_conf="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp_gen}' '${tmp_conf}'" RETURN

  backup_file "/etc/locale.gen"
  cp /etc/locale.gen "${tmp_gen}" 2>/dev/null || true

  # Source: aur-wiki-locale.txt — "uncommenting applicable entries in /etc/locale.gen"
  # Uncomment the entry if it exists as a comment; otherwise append it.
  _uncomment_or_append_locale "${locale}" "${tmp_gen}"

  # Source: aur-wiki-locale.txt — "in addition to en_US.UTF-8 UTF-8 which is commonly
  # used as a fallback for various tools"
  if [[ "${locale}" != "en_US.UTF-8" ]]; then
    if ! grep -q "^en_US.UTF-8 UTF-8" "${tmp_gen}" 2>/dev/null; then
      log_info "Adding en_US.UTF-8 as fallback locale (recommended by Arch Wiki)."
      _uncomment_or_append_locale "en_US.UTF-8" "${tmp_gen}"
    fi
  fi

  run_cmd sudo cp "${tmp_gen}" /etc/locale.gen
  run_cmd sudo locale-gen

  # Source: aur-wiki-locale.txt — "Setting the system locale":
  # "write the LANG variable to /etc/locale.conf"
  backup_file "/etc/locale.conf"
  echo "LANG=${locale}" > "${tmp_conf}"
  run_cmd sudo cp "${tmp_conf}" /etc/locale.conf
  log_ok "Locale set to ${locale}."
  log_info "Changes take effect on next login. To apply now: unset LANG && source /etc/profile.d/locale.sh"
}

# Uncomment "#locale UTF-8" in file, or append "locale UTF-8" if not found.
_uncomment_or_append_locale() {
  local locale_entry="$1"
  local file="$2"

  if grep -q "^${locale_entry} UTF-8" "${file}" 2>/dev/null; then
    # Already active — nothing to do
    log_skip "${locale_entry} already active in locale.gen."
    return 0
  fi

  if grep -q "^#${locale_entry} UTF-8" "${file}" 2>/dev/null; then
    # Commented entry exists — uncomment it
    sed -i "s/^#${locale_entry} UTF-8/${locale_entry} UTF-8/" "${file}"
  else
    # Entry not found — append it
    printf '%s UTF-8\n' "${locale_entry}" >> "${file}"
  fi
}

# ── Timezone ──────────────────────────────────────────────────────────────────
_configure_timezone() {
  # Source: aur-wiki-system-time.txt — "Time zone":
  # "To set your time zone: timedatectl set-timezone Area/Location"
  # "systemd-timesyncd — A simple SNTP daemon... should be more than appropriate for most installations"

  log_info "Current timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || true)"

  local tz=""
  if [[ "${YES_FLAG:-false}" == "true" && -t 0 ]]; then
    :
  elif command -v fzf &>/dev/null && [[ -t 0 ]]; then
    tz="$(timedatectl list-timezones 2>/dev/null | fzf --prompt="Select timezone: " || true)"
  else
    read -r -p "Timezone (e.g. America/New_York — blank to skip): " tz || true
  fi

  if [[ -n "${tz}" ]]; then
    run_cmd sudo timedatectl set-timezone "${tz}"
    # Source: aur-wiki-system-time.txt — "systemd-timesyncd" (SNTP, appropriate for most installations)
    run_cmd sudo timedatectl set-ntp true
    log_ok "Timezone set to ${tz}, NTP enabled."
  fi
}

# ── Hardware clock ────────────────────────────────────────────────────────────
_configure_hardware_clock() {
  # Source: aur-wiki-system-time.txt — "Time standard":
  # "If multiple operating systems are installed on a machine... recommended to set it to
  #  UTC to avoid conflicts across systems."
  # "To revert to the hardware clock being in UTC: timedatectl set-local-rtc 0"
  # "Set hardware clock from system clock: hwclock --systohc"

  local rtc_in_local
  rtc_in_local="$(timedatectl show --property=LocalRTC --value 2>/dev/null || echo 'no')"
  local current_std
  if [[ "${rtc_in_local}" == "yes" ]]; then
    current_std="localtime"
  else
    current_std="UTC"
  fi
  log_info "Current hardware clock standard: ${current_std}"

  echo ""
  echo "Hardware clock time standard:"
  echo "  [1] UTC [★ recomendado] — safe for single-OS and dual-boot with Linux/macOS"
  echo "  [2] localtime           — required only for dual-boot with Windows (without registry fix)"
  echo "  [s] Skip"
  echo ""
  # Source: aur-wiki-system-time.txt — "UTC in Microsoft Windows":
  # "To dual boot with Windows, it is recommended to configure Windows to use UTC,
  #  rather than Linux to use localtime."
  log_info "Tip: Windows can be configured to use UTC via a registry fix — see aur-wiki-system-time.txt."

  local hw_choice="1"
  if [[ "${YES_FLAG:-false}" == "true" && -t 0 ]]; then
    hw_choice="1"
  else
    read -r -p "Choice [1]: " hw_choice || true
  fi

  case "${hw_choice:-1}" in
    1)
      # Source: aur-wiki-system-time.txt line 112: "timedatectl set-local-rtc 0"
      run_cmd sudo timedatectl set-local-rtc 0
      log_ok "Hardware clock set to UTC standard."
      ;;
    2)
      # Source: aur-wiki-system-time.txt line 108: "timedatectl set-local-rtc 1"
      log_warn "localtime standard may cause issues on single-OS systems and during DST changes."
      log_warn "Recommended: configure Windows to use UTC instead (registry fix — see wiki)."
      run_cmd sudo timedatectl set-local-rtc 1
      log_ok "Hardware clock set to localtime standard."
      ;;
    s|S)
      log_skip "Hardware clock standard unchanged."
      return 0
      ;;
    *)
      log_warn "Invalid choice — skipping hardware clock configuration."
      return 0
      ;;
  esac

  # Source: aur-wiki-system-time.txt line 64:
  # "Set hardware clock from system clock: hwclock --systohc"
  # "Additionally it updates /etc/adjtime or creates it if not present."
  if [[ "${ARCHFORGE_TEST:-false}" != "true" ]]; then
    run_cmd sudo hwclock --systohc
    log_ok "Hardware clock synced from system clock (hwclock --systohc)."
  fi
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
