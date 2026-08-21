#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true DRY_RUN=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  mock_reset
}

@test "systemd module_info has MODULE_WIKI_SOURCE referencing systemd" {
  source "$ARCHFORGE_DIR/modules/02-system-services/systemd.sh"
  module_info
  [[ "${MODULE_WIKI_SOURCE}" == *"aur-wiki-systemd"* ]]
}

@test "systemd module_info has MODULE_NAME set" {
  source "$ARCHFORGE_DIR/modules/02-system-services/systemd.sh"
  module_info
  [[ -n "${MODULE_NAME}" ]]
}

@test "systemd module_run dry-run exits 0" {
  source "$ARCHFORGE_DIR/modules/02-system-services/systemd.sh"
  run module_run
  [ "$status" -eq 0 ]
}

@test "systemd module_run completes in dry-run mode" {
  source "$ARCHFORGE_DIR/modules/02-system-services/systemd.sh"
  run module_run
  [ "$status" -eq 0 ]
}

@test "systemd module_run backs up system.conf" {
  source "$ARCHFORGE_DIR/modules/02-system-services/systemd.sh"
  module_run
  mock_backed_up "/etc/systemd/system.conf"
}
