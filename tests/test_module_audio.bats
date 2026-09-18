#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true DRY_RUN=false YES_FLAG=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  source "$ARCHFORGE_DIR/lib/menu.sh"
  source "$ARCHFORGE_DIR/modules/12-peripherals/audio.sh"
  mock_reset
}

@test "audio module_info exposes required metadata and official ArchWiki sources" {
  module_info
  [ -n "${MODULE_NAME}" ]
  [[ "${MODULE_PACKAGES}" == *"pipewire"* ]]
  [[ "${MODULE_PACKAGES}" == *"pipewire-pulse"* ]]
  [[ "${MODULE_PACKAGES}" == *"wireplumber"* ]]
  [[ "${MODULE_WIKI_SOURCE}" == *"aur-wiki-pipewire.txt"* ]]
  [[ "${MODULE_WIKI_SOURCE}" == *"aur-wiki-wireplumber.txt"* ]]

  local urls
  urls="$(wiki_source_to_urls "${MODULE_WIKI_SOURCE}")"
  [[ "${urls}" == *"https://wiki.archlinux.org/title/PipeWire"* ]]
  [[ "${urls}" == *"https://wiki.archlinux.org/title/WirePlumber"* ]]
}

@test "audio module_run in dry-run mode exits 0" {
  export DRY_RUN=true
  run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"PipeWire and WirePlumber audio stack installed and configured"* ]]
}

@test "audio module_run installs core pipewire stack and enables user units" {
  module_run

  # Verify core packages installed
  mock_installed "pipewire"
  mock_installed "pipewire-audio"
  mock_installed "pipewire-pulse"
  mock_installed "pipewire-alsa"
  mock_installed "wireplumber"

  # Verify user units enabled via enable_user_service
  mock_ran "sudo systemctl --global enable pipewire.service"
  mock_ran "sudo systemctl --global enable pipewire-pulse.service"
  mock_ran "sudo systemctl --global enable wireplumber.service"
}

@test "audio module_run installs pipewire-jack when confirmed" {
  export YES_FLAG=false
  # Confirm pipewire-jack ('y') and decline pavucontrol ('n')
  printf 'y\nn\n' | module_run

  mock_installed "pipewire-jack"
}

@test "audio module_run skips pipewire-jack when declined" {
  export YES_FLAG=false
  # Decline pipewire-jack ('n') and decline pavucontrol ('n')
  printf 'n\nn\n' | module_run

  ! grep -q "pipewire-jack" "${MOCK_PKG_LOG}"
}

@test "audio module_run installs pavucontrol when confirmed" {
  export YES_FLAG=false
  # Decline pipewire-jack ('n') and confirm pavucontrol ('y')
  printf 'n\ny\n' | module_run

  mock_installed "pavucontrol"
}

@test "audio module_run skips pavucontrol when declined" {
  export YES_FLAG=false
  # Decline pipewire-jack ('n') and decline pavucontrol ('n')
  printf 'n\nn\n' | module_run

  ! grep -q "pavucontrol" "${MOCK_PKG_LOG}"
}

@test "audio module_run alerts when legacy pulseaudio is detected" {
  # Mock pkg_installed to report pulseaudio as installed
  pkg_installed() {
    [[ "$1" == "pulseaudio" ]] && return 0
    return 1
  }

  run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Legacy PulseAudio detected"* ]]
}

@test "preview_module produces card with ArchWiki URLs for audio" {
  _find_module_file() {
    echo "$ARCHFORGE_DIR/modules/12-peripherals/audio.sh"
  }
  run preview_module "audio"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Peripherals: Audio"* ]]
  [[ "$output" == *"https://wiki.archlinux.org/title/PipeWire"* ]]
  [[ "$output" == *"https://wiki.archlinux.org/title/WirePlumber"* ]]
  [[ "$output" == *"pipewire pipewire-audio pipewire-pulse pipewire-alsa wireplumber"* ]]
}
