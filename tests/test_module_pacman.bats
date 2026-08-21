#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  mock_reset
  if [[ ! -f /etc/pacman.conf ]]; then
    export PACMAN_CONF="/tmp/archforge-test-pacman-$$.conf"
    echo "[options]" > "$PACMAN_CONF"
  fi
}

@test "pacman module_info has all required fields" {
  source "$ARCHFORGE_DIR/modules/01-package-management/pacman.sh"
  module_info
  [[ -n "$MODULE_NAME" ]]
  [[ -n "$MODULE_WIKI_SOURCE" ]]
  [[ -n "$MODULE_PACKAGES" ]]
  [[ "$MODULE_REQUIRES_ROOT" == "true" ]]
}

@test "pacman module_run in dry-run mode exits 0" {
  export DRY_RUN=true
  source "$ARCHFORGE_DIR/modules/01-package-management/pacman.sh"
  run module_run
  [ "$status" -eq 0 ]
}

@test "pacman module_run backs up pacman.conf" {
  export DRY_RUN=true
  source "$ARCHFORGE_DIR/modules/01-package-management/pacman.sh"
  module_run
  mock_backed_up "${PACMAN_CONF:-/etc/pacman.conf}"
}

@test "aur-helper module_info has MODULE_WIKI_SOURCE" {
  source "$ARCHFORGE_DIR/modules/01-package-management/aur-helper.sh"
  module_info
  [[ -n "$MODULE_WIKI_SOURCE" ]]
}

@test "aur-helper module_run exits 0 when AUR_HELPER already set" {
  export DRY_RUN=true
  export AUR_HELPER="yay"
  source "$ARCHFORGE_DIR/modules/01-package-management/aur-helper.sh"
  run module_run
  [ "$status" -eq 0 ]
}
