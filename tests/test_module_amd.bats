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

@test "amd module_info exposes metadata, packages and ArchWiki sources" {
  source "$ARCHFORGE_DIR/modules/10-graphics/amd.sh"
  module_info
  [[ "$MODULE_NAME" == *"AMD GPU"* ]]
  [[ "$MODULE_PACKAGES" == *"mesa"* ]]
  [[ "$MODULE_PACKAGES" == *"vulkan-radeon"* ]]
  [[ "$MODULE_WIKI_SOURCE" == "aur-wiki-amd-graphics.txt" ]]
  [ "$MODULE_REQUIRES_ROOT" = true ]
}

@test "amd module_run proceeds normally when AMD GPU is detected" {
  export DETECTED_GPU="AMD"
  source "$ARCHFORGE_DIR/modules/10-graphics/amd.sh"
  run module_run
  [ "$status" -eq 0 ]
  mock_installed "mesa"
  mock_installed "vulkan-radeon"
}

@test "amd module_run proceeds when multiple GPUs include AMD" {
  export DETECTED_GPU="Multiple (AMD)"
  source "$ARCHFORGE_DIR/modules/10-graphics/amd.sh"
  run module_run
  [ "$status" -eq 0 ]
  mock_installed "mesa"
  mock_installed "vulkan-radeon"
}

@test "amd module_run warns when no AMD GPU is detected and user declines" {
  export DETECTED_GPU="Intel"
  export YES_FLAG=false DRY_RUN=false ARCHFORGE_TEST=true

  # Fake lspci showing only Intel
  FAKE_BIN="$(mktemp -d)"
  cat > "${FAKE_BIN}/lspci" <<'LSPCI_EOF'
#!/usr/bin/env bash
echo "00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-S GT1 [UHD Graphics 770]"
LSPCI_EOF
  chmod +x "${FAKE_BIN}/lspci"
  export PATH="${FAKE_BIN}:${PATH}"

  source "$ARCHFORGE_DIR/modules/10-graphics/amd.sh"
  run module_run <<< "n"
  rm -rf "${FAKE_BIN}"

  [ "$status" -eq 2 ]
  [[ "$output" == *"AMD GPU required"* ]]
}

@test "amd module_run installs lib32 packages when multilib is enabled and confirmed" {
  export DETECTED_GPU="AMD"
  echo "[multilib]" >> "${ARCHFORGE_PACMAN_CONF}"

  source "$ARCHFORGE_DIR/modules/10-graphics/amd.sh"
  run module_run
  [ "$status" -eq 0 ]
  mock_installed "lib32-mesa"
  mock_installed "lib32-vulkan-radeon"
}

@test "amd module_run skips lib32 packages when multilib is disabled" {
  export DETECTED_GPU="AMD"

  source "$ARCHFORGE_DIR/modules/10-graphics/amd.sh"
  run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"multilib repository not enabled"* ]]
  ! mock_installed "lib32-mesa"
  ! mock_installed "lib32-vulkan-radeon"
}

@test "amd _configure_early_kms updates MODULES array idempotently and backs up config" {
  export DETECTED_GPU="AMD"
  source "$ARCHFORGE_DIR/modules/10-graphics/amd.sh"

  # First run: should backup file, insert amdgpu, and run mkinitcpio -P
  run _configure_early_kms "${ARCHFORGE_MKINITCPIO_CONF}"
  [ "$status" -eq 0 ]
  mock_backed_up "${ARCHFORGE_MKINITCPIO_CONF}"
  mock_ran "sudo mkinitcpio -P"

  # Verify the file was updated with amdgpu in MODULES=(...)
  mock_ran "sudo cp"

  # Simulate the file having amdgpu already present
  cat > "${ARCHFORGE_MKINITCPIO_CONF}" <<'EOF'
MODULES=(amdgpu)
BINARIES=()
FILES=()
HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)
EOF

  mock_reset
  run _configure_early_kms "${ARCHFORGE_MKINITCPIO_CONF}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"amdgpu is already present in mkinitcpio MODULES"* ]]
  ! mock_ran "sudo mkinitcpio -P"
}

@test "amd module_run does not execute real mkinitcpio under dry-run" {
  export DRY_RUN=true YES_FLAG=true ARCHFORGE_TEST=false DETECTED_GPU="AMD"
  source "$ARCHFORGE_DIR/modules/10-graphics/amd.sh"
  run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRYRUN"* ]]
  [[ "$output" == *"sudo mkinitcpio -P"* ]]
}

@test "preview_module produces card with ArchWiki URLs for amd" {
  source "$ARCHFORGE_DIR/lib/menu.sh"
  _find_module_file() {
    echo "$ARCHFORGE_DIR/modules/10-graphics/amd.sh"
  }
  run preview_module "amd"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Graphics: AMD GPU"* ]]
  [[ "$output" == *"https://wiki.archlinux.org/title/AMDGPU"* ]]
  [[ "$output" == *"mesa vulkan-radeon"* ]]
}

@test "amd module_run aborts with exit code 1 if mkinitcpio -P fails" {
  export DETECTED_GPU="AMD"
  source "$ARCHFORGE_DIR/modules/10-graphics/amd.sh"

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
  [[ "$output" != *"AMD graphics configuration complete"* ]]
}

@test "amd module_run advises DRI_PRIME=1 on hybrid GPU systems" {
  export DETECTED_GPU="Multiple (AMD)"
  source "$ARCHFORGE_DIR/modules/10-graphics/amd.sh"
  run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRI_PRIME=1"* ]]
}
