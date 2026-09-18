#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true DRY_RUN=false YES_FLAG=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  source "$ARCHFORGE_DIR/lib/menu.sh"
  source "$ARCHFORGE_DIR/modules/12-peripherals/bluetooth.sh"
  mock_reset
}

@test "bluetooth module_info exposes metadata, ArchWiki sources, and audio dependency" {
  module_info
  [ -n "${MODULE_NAME}" ]
  [[ "${MODULE_PACKAGES}" == *"bluez"* ]]
  [[ "${MODULE_PACKAGES}" == *"bluez-utils"* ]]
  [[ "${MODULE_WIKI_SOURCE}" == *"aur-wiki-bluetooth.txt"* ]]
  [[ "${MODULE_DEPENDS}" == *"audio"* ]]

  local urls
  urls="$(wiki_source_to_urls "${MODULE_WIKI_SOURCE}")"
  [[ "${urls}" == *"https://wiki.archlinux.org/title/Bluetooth"* ]]
}

@test "bluetooth module_run in dry-run mode exits 0" {
  export DRY_RUN=true
  run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bluetooth stack installed and service enabled"* ]]
}

@test "bluetooth module_run installs core packages and enables bluetooth.service" {
  module_run

  mock_installed "bluez"
  mock_installed "bluez-utils"
  mock_ran "sudo systemctl enable --now bluetooth.service"
}

@test "bluetooth module_run installs blueman when confirmed" {
  export YES_FLAG=false
  printf 'y\n' | module_run

  mock_installed "blueman"
}

@test "bluetooth module_run skips blueman when declined" {
  export YES_FLAG=false
  printf 'n\n' | module_run

  ! grep -q "blueman" "${MOCK_PKG_LOG}"
}

@test "bluetooth module_run detects soft-blocked rfkill and issues unblock command" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/rfkill" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"list bluetooth"* ]]; then
  echo "0: hci0: Bluetooth"
  echo "	Soft blocked: yes"
  echo "	Hard blocked: no"
fi
EOF
  chmod +x "${fake_bin}/rfkill"

  PATH="${fake_bin}:${PATH}" module_run

  mock_ran "sudo rfkill unblock bluetooth"
  rm -rf "${fake_bin}"
}

@test "bluetooth module_run detects hard-blocked rfkill and warns cleanly without unblocking" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/rfkill" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"list bluetooth"* ]]; then
  echo "0: hci0: Bluetooth"
  echo "	Soft blocked: no"
  echo "	Hard blocked: yes"
fi
EOF
  chmod +x "${fake_bin}/rfkill"

  PATH="${fake_bin}:${PATH}" run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"hard-blocked by physical airplane mode switch"* ]]
  ! mock_ran "sudo rfkill unblock bluetooth"

  rm -rf "${fake_bin}"
}

@test "bluetooth module_run checks audio integration and logs accordingly" {
  # Case A: pipewire-audio present
  pkg_installed() {
    [[ "$1" == "pipewire-audio" ]] && return 0
    return 1
  }
  run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"PipeWire audio stack detected"* ]]

  # Case B: pipewire-audio absent
  pkg_installed() { return 1; }
  run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"For Bluetooth audio (headsets/speakers), install the 'audio' module"* ]]
}

@test "preview_module produces card with ArchWiki URLs and audio dependency for bluetooth" {
  _find_module_file() {
    echo "$ARCHFORGE_DIR/modules/12-peripherals/bluetooth.sh"
  }
  run preview_module "bluetooth"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Peripherals: Bluetooth"* ]]
  [[ "$output" == *"https://wiki.archlinux.org/title/Bluetooth"* ]]
  [[ "$output" == *"bluez bluez-utils"* ]]
  [[ "$output" == *"DEPENDENCIAS DE MÓDULO:"* ]]
  [[ "$output" == *"audio"* ]]
}
