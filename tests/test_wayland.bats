#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true YES_FLAG=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  mock_reset

  FAKE_BIN="$(mktemp -d)"
  cat > "${FAKE_BIN}/lspci" <<'LSPCI_EOF'
#!/usr/bin/env bash
echo "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation Device [10de:2204] (rev a1)"
LSPCI_EOF
  chmod +x "${FAKE_BIN}/lspci"
  export PATH="${FAKE_BIN}:${PATH}"
}

teardown() {
  rm -rf "${FAKE_BIN}"
}

@test "nvidia.sh enables fbdev=1 and modeset=1 for Wayland compatibility" {
  # Hyprland Wiki: https://wiki.hypr.land/Nvidia/
  run grep -q 'options nvidia_drm modeset=1 fbdev=1' "$ARCHFORGE_DIR/modules/10-graphics/nvidia.sh"
  [ "$status" -eq 0 ]
}

@test "nvidia.sh configures early KMS modules for initramfs" {
  # ArchWiki: https://wiki.archlinux.org/title/NVIDIA#Early_loading
  # Hyprland Wiki: https://wiki.hypr.land/Nvidia/
  run grep -q 'nvidia nvidia_modeset nvidia_uvm nvidia_drm' "$ARCHFORGE_DIR/modules/10-graphics/nvidia.sh"
  [ "$status" -eq 0 ]
}

@test "nvidia.sh writes Wayland environment variables drop-in" {
  # Hyprland Wiki: https://wiki.hypr.land/Nvidia/
  run grep -q '/etc/environment.d/10-nvidia-wayland.conf' "$ARCHFORGE_DIR/modules/10-graphics/nvidia.sh"
  [ "$status" -eq 0 ]
  run grep -q 'LIBVA_DRIVER_NAME=nvidia' "$ARCHFORGE_DIR/modules/10-graphics/nvidia.sh"
  [ "$status" -eq 0 ]
}

@test "libinput.sh includes Wayland and Hyprland input configuration support" {
  # Hyprland Wiki: https://wiki.hypr.land/Configuring/Variables/#input
  run grep -q 'Hyprland Wiki:' "$ARCHFORGE_DIR/modules/06-input/libinput.sh"
  [ "$status" -eq 0 ]
  run grep -q 'tap-to-click' "$ARCHFORGE_DIR/modules/06-input/libinput.sh"
  [ "$status" -eq 0 ]
  run grep -q 'natural_scroll' "$ARCHFORGE_DIR/modules/06-input/libinput.sh"
  [ "$status" -eq 0 ]
}

@test "fonts.sh includes ttf-jetbrains-mono-nerd for Wayland status bars" {
  source "$ARCHFORGE_DIR/modules/08-console/fonts.sh"
  module_info
  [[ "$MODULE_PACKAGES" == *"ttf-jetbrains-mono-nerd"* ]]
}
