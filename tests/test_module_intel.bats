#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true YES_FLAG=true DRY_RUN=false
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  mock_reset

  TEST_TMP_DIR="$(mktemp -d)"
  export ARCHFORGE_MKINITCPIO_CONF="${TEST_TMP_DIR}/mkinitcpio.conf"
  export ARCHFORGE_PACMAN_CONF="${TEST_TMP_DIR}/pacman.conf"

  cat > "${ARCHFORGE_MKINITCPIO_CONF}" <<'EOF'
MODULES=()
BINARIES=()
FILES=()
HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)
EOF

  cat > "${ARCHFORGE_PACMAN_CONF}" <<'EOF'
[options]
Architecture = auto
[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
EOF
}

teardown() {
  rm -rf "${TEST_TMP_DIR}"
}

@test "intel module_info exposes metadata, packages and ArchWiki sources" {
  source "$ARCHFORGE_DIR/modules/10-graphics/intel.sh"
  module_info
  [[ "$MODULE_NAME" == *"Intel Graphics"* ]]
  [[ "$MODULE_PACKAGES" == *"mesa"* ]]
  [[ "$MODULE_PACKAGES" == *"vulkan-intel"* ]]
  [[ "$MODULE_PACKAGES" == *"intel-media-driver"* ]]
  [[ "$MODULE_WIKI_SOURCE" == "aur-wiki-intel-graphics.txt" ]]
  [ "$MODULE_REQUIRES_ROOT" = true ]
}

@test "intel module_run proceeds normally when Intel GPU is detected" {
  export DETECTED_GPU="Intel"
  source "$ARCHFORGE_DIR/modules/10-graphics/intel.sh"
  run module_run
  [ "$status" -eq 0 ]
  mock_installed "mesa"
  mock_installed "vulkan-intel"
  mock_installed "intel-media-driver"
}

@test "intel module_run proceeds when multiple GPUs include Intel" {
  export DETECTED_GPU="Multiple (Intel)"
  source "$ARCHFORGE_DIR/modules/10-graphics/intel.sh"
  run module_run
  [ "$status" -eq 0 ]
  mock_installed "mesa"
  mock_installed "vulkan-intel"
  mock_installed "intel-media-driver"
}

@test "intel module_run warns when no Intel GPU is detected and user declines" {
  export DETECTED_GPU="AMD"
  export YES_FLAG=false DRY_RUN=false ARCHFORGE_TEST=true

  # Fake lspci showing only AMD
  FAKE_BIN="$(mktemp -d)"
  cat > "${FAKE_BIN}/lspci" <<'LSPCI_EOF'
#!/usr/bin/env bash
echo "03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX 6700/6700 XT/6750 XT / 6800M/6850M XT]"
LSPCI_EOF
  chmod +x "${FAKE_BIN}/lspci"
  export PATH="${FAKE_BIN}:${PATH}"

  source "$ARCHFORGE_DIR/modules/10-graphics/intel.sh"
  run module_run <<< "n"
  rm -rf "${FAKE_BIN}"

  [ "$status" -eq 2 ]
  [[ "$output" == *"Intel GPU required"* ]]
}

@test "intel _select_vaapi_driver respects user choice for legacy libva-intel-driver" {
  export YES_FLAG=false DRY_RUN=false ARCHFORGE_TEST=false
  source "$ARCHFORGE_DIR/modules/10-graphics/intel.sh"
  run _select_vaapi_driver <<< "2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"libva-intel-driver"* ]]
}

@test "intel _select_vaapi_driver respects user choice to skip" {
  export YES_FLAG=false DRY_RUN=false ARCHFORGE_TEST=false
  source "$ARCHFORGE_DIR/modules/10-graphics/intel.sh"
  local choice
  choice="$(_select_vaapi_driver 2>/dev/null <<< "s")"
  [ -z "$choice" ]
}

@test "intel module_run installs lib32 packages when multilib is enabled and confirmed" {
  export DETECTED_GPU="Intel"
  echo "[multilib]" >> "${ARCHFORGE_PACMAN_CONF}"

  source "$ARCHFORGE_DIR/modules/10-graphics/intel.sh"
  run module_run
  [ "$status" -eq 0 ]
  mock_installed "lib32-mesa"
  mock_installed "lib32-vulkan-intel"
}

@test "intel module_run skips lib32 packages when multilib is disabled" {
  export DETECTED_GPU="Intel"

  source "$ARCHFORGE_DIR/modules/10-graphics/intel.sh"
  run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"multilib repository not enabled"* ]]
  ! mock_installed "lib32-mesa"
  ! mock_installed "lib32-vulkan-intel"
}

@test "intel _configure_intel_early_kms updates MODULES array idempotently and backs up config" {
  export DETECTED_GPU="Intel"
  source "$ARCHFORGE_DIR/modules/10-graphics/intel.sh"

  # First run: should backup file, insert i915, and run mkinitcpio -P
  run _configure_intel_early_kms "${ARCHFORGE_MKINITCPIO_CONF}"
  [ "$status" -eq 0 ]
  mock_backed_up "${ARCHFORGE_MKINITCPIO_CONF}"
  mock_ran "sudo mkinitcpio -P"
  mock_ran "sudo cp"

  # Simulate the file having i915 already present
  cat > "${ARCHFORGE_MKINITCPIO_CONF}" <<'EOF'
MODULES=(i915)
BINARIES=()
FILES=()
HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)
EOF

  mock_reset
  run _configure_intel_early_kms "${ARCHFORGE_MKINITCPIO_CONF}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"i915 is already present in mkinitcpio MODULES"* ]]
  ! mock_ran "sudo mkinitcpio -P"
}

@test "intel module_run does not execute real pacman or mkinitcpio under dry-run" {
  export DRY_RUN=true YES_FLAG=true ARCHFORGE_TEST=false DETECTED_GPU="Intel"
  source "$ARCHFORGE_DIR/modules/10-graphics/intel.sh"
  run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRYRUN"* ]]
  [[ "$output" == *"intel-media-driver"* ]]
  [[ "$output" == *"sudo mkinitcpio -P"* ]]
}

@test "intel _configure_intel_early_kms simulates mkinitcpio under dry-run without real execution" {
  export DRY_RUN=true YES_FLAG=true ARCHFORGE_TEST=false
  source "$ARCHFORGE_DIR/modules/10-graphics/intel.sh"
  run _configure_intel_early_kms "${ARCHFORGE_MKINITCPIO_CONF}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRYRUN"* ]]
  [[ "$output" == *"sudo mkinitcpio -P"* ]]
}

@test "intel module_run aborts with exit code 1 if mkinitcpio -P fails" {
  export DETECTED_GPU="Intel"
  source "$ARCHFORGE_DIR/modules/10-graphics/intel.sh"

  # Override run_cmd to fail on mkinitcpio
  run_cmd() {
    if [[ "$*" == *"mkinitcpio -P"* ]]; then
      return 1
    fi
    echo "$*" >> "${MOCK_LOG_FILE}"
    return 0
  }

  run module_run
  [ "$status" -eq 1 ]
  [[ "$output" == *"mkinitcpio -P failed"* ]]
  [[ "$output" != *"Intel graphics configuration complete"* ]]
}

@test "intel module_run logs hybrid GPU notice on multiple GPUs" {
  export DETECTED_GPU="Multiple (Intel)"
  source "$ARCHFORGE_DIR/modules/10-graphics/intel.sh"
  run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hybrid graphics detected"* ]]
}

@test "preview_module produces card with ArchWiki URLs for intel" {
  source "$ARCHFORGE_DIR/lib/menu.sh"
  _find_module_file() {
    echo "$ARCHFORGE_DIR/modules/10-graphics/intel.sh"
  }
  run preview_module "intel"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Graphics: Intel Graphics"* ]]
  [[ "$output" == *"https://wiki.archlinux.org/title/Intel_graphics"* ]]
  [[ "$output" == *"mesa vulkan-intel intel-media-driver"* ]]
}
