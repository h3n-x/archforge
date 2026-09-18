#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true DRY_RUN=false YES_FLAG=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  source "$ARCHFORGE_DIR/modules/07-optimization/sensors.sh"
  mock_reset
}

@test "sensors module_info exposes required metadata and official ArchWiki sources" {
  module_info
  [ -n "${MODULE_NAME}" ]
  [[ "${MODULE_PACKAGES}" == *"lm_sensors"* ]]
  [[ "${MODULE_WIKI_SOURCE}" == *"aur-wiki-lm-sensors.txt"* ]]
  [[ "${MODULE_WIKI_SOURCE}" == *"aur-wiki-fan-speed-control.txt"* ]]
}

@test "sensors module_run installs lm_sensors package" {
  module_run
  mock_installed "lm_sensors"
}

@test "sensors module_run executes sensors-detect in test mode" {
  module_run
  mock_ran "sudo sensors-detect --auto"
}

@test "sensors module_run displays readings when sensors command succeeds" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/sensors" <<'EOF'
#!/usr/bin/env bash
echo "coretemp-isa-0000"
echo "Package id 0:  +45.0°C"
EOF
  chmod +x "${fake_bin}/sensors"

  PATH="${fake_bin}:${PATH}" run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"coretemp-isa-0000"* ]]
  [[ "$output" == *"Package id 0"* ]]

  rm -rf "${fake_bin}"
}

@test "sensors module_run warns cleanly when sensors command fails" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/sensors" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${fake_bin}/sensors"

  PATH="${fake_bin}:${PATH}" run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"sensors command failed — reboot may be required first"* ]]

  rm -rf "${fake_bin}"
}

@test "sensors module_run advises pwmconfig when fancontrol is confirmed" {
  export YES_FLAG=true
  run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"fancontrol is included with lm_sensors"* ]]
  [[ "$output" == *"Run 'sudo pwmconfig' manually"* ]]
}

@test "sensors module_run skips fancontrol advice when user declines" {
  export YES_FLAG=false
  # Supply 'n' to fancontrol confirm prompt
  run bash -c "printf 'n\n' | { source '$ARCHFORGE_DIR/lib/core.sh'; source '$ARCHFORGE_DIR/lib/packages.sh'; source '$ARCHFORGE_DIR/modules/07-optimization/sensors.sh'; module_run; }"
  [ "$status" -eq 0 ]
  [[ "$output" != *"fancontrol is included with lm_sensors"* ]]
  [[ "$output" != *"Run 'sudo pwmconfig' manually"* ]]
}
