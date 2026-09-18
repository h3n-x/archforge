#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true DRY_RUN=false YES_FLAG=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  source "$ARCHFORGE_DIR/modules/08-console/locale.sh"
  mock_reset
}

@test "locale module_info exposes metadata and official ArchWiki sources" {
  module_info
  [ -n "${MODULE_NAME}" ]
  [[ "${MODULE_WIKI_SOURCE}" == *"aur-wiki-locale.txt"* ]]
  [[ "${MODULE_WIKI_SOURCE}" == *"aur-wiki-system-time.txt"* ]]
}

@test "_uncomment_or_append_locale uncomments a commented locale entry in locale.gen" {
  local tmp_gen; tmp_gen="$(mktemp)"
  cat > "${tmp_gen}" <<'EOF'
#  en_GB.ISO-8859-15 ISO-8859-15
#en_US.UTF-8 UTF-8
#es_ES.UTF-8 UTF-8
EOF

  _uncomment_or_append_locale "es_ES.UTF-8" "${tmp_gen}"
  run grep "^es_ES.UTF-8 UTF-8" "${tmp_gen}"
  [ "$status" -eq 0 ]
  run grep "^#es_ES.UTF-8 UTF-8" "${tmp_gen}"
  [ "$status" -ne 0 ]

  rm -f "${tmp_gen}"
}

@test "_uncomment_or_append_locale is idempotent when locale is already active" {
  local tmp_gen; tmp_gen="$(mktemp)"
  echo "es_ES.UTF-8 UTF-8" > "${tmp_gen}"

  _uncomment_or_append_locale "es_ES.UTF-8" "${tmp_gen}"
  local count
  count="$(grep -c "^es_ES.UTF-8 UTF-8" "${tmp_gen}")"
  [ "${count}" -eq 1 ]

  rm -f "${tmp_gen}"
}

@test "_uncomment_or_append_locale appends locale if not found in file" {
  local tmp_gen; tmp_gen="$(mktemp)"
  echo "#en_US.UTF-8 UTF-8" > "${tmp_gen}"

  _uncomment_or_append_locale "de_DE.UTF-8" "${tmp_gen}"
  run grep "^de_DE.UTF-8 UTF-8" "${tmp_gen}"
  [ "$status" -eq 0 ]

  rm -f "${tmp_gen}"
}

@test "_configure_locale backs up files and runs locale-gen" {
  # Feed valid locale via stdin
  printf "es_ES.UTF-8\n" | _configure_locale
  mock_backed_up "/etc/locale.gen"
  mock_backed_up "/etc/locale.conf"
  mock_ran "sudo locale-gen"
  mock_ran "sudo cp "
}

@test "_configure_timezone sets timezone and enables timesyncd NTP" {
  printf "America/New_York\n" | _configure_timezone
  mock_ran "sudo timedatectl set-timezone America/New_York"
  mock_ran "sudo timedatectl set-ntp true"
}

@test "_configure_timezone skips when input is blank" {
  printf "\n" | _configure_timezone
  run cat "${MOCK_LOG_FILE}"
  [[ "$output" != *"timedatectl set-timezone"* ]]
}

@test "_configure_hardware_clock sets UTC standard for choice 1" {
  printf "1\n" | _configure_hardware_clock
  mock_ran "sudo timedatectl set-local-rtc 0"
}

@test "_configure_hardware_clock sets localtime standard for choice 2" {
  printf "2\n" | _configure_hardware_clock
  mock_ran "sudo timedatectl set-local-rtc 1"
}

@test "_configure_hardware_clock skips when choice is 's'" {
  printf "s\n" | _configure_hardware_clock
  run cat "${MOCK_LOG_FILE}"
  [[ "$output" != *"timedatectl set-local-rtc"* ]]
}
