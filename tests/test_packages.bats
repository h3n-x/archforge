#!/usr/bin/env bats
load 'setup'

setup() {
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  mock_reset
}

@test "pkg_installed returns 0 for bash (always installed on Arch)" {
  if ! command -v pacman &>/dev/null; then
    skip "pacman not installed on test host"
  fi
  run pkg_installed bash
  [ "$status" -eq 0 ]
}

@test "pkg_installed returns 1 for definitely-not-a-package-xyz" {
  run pkg_installed "definitely-not-a-package-xyz-$$"
  [ "$status" -ne 0 ]
}

@test "pacman_install records call in test mode" {
  export ARCHFORGE_TEST=true
  pacman_install "somepkg"
  mock_installed "somepkg"
}

@test "aur_install skips with warning when AUR_HELPER is empty" {
  export AUR_HELPER=""
  run aur_install "some-aur-pkg"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"* ]]
}

@test "aur_install records call in test mode when AUR_HELPER is set" {
  export ARCHFORGE_TEST=true
  export AUR_HELPER="yay"
  aur_install "some-aur-pkg"
  mock_aur_installed "some-aur-pkg"
}

@test "detect_aur_helper sets AUR_HELPER when a helper exists" {
  # This test only runs if at least one AUR helper is installed
  if ! command -v yay &>/dev/null && ! command -v paru &>/dev/null && \
     ! command -v trizen &>/dev/null && ! command -v pikaur &>/dev/null; then
    skip "No AUR helper installed on this machine"
  fi
  detect_aur_helper
  [[ -n "$AUR_HELPER" ]]
}
