#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true YES_FLAG=true DRY_RUN=false
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  source "$ARCHFORGE_DIR/lib/menu.sh"
  source "$ARCHFORGE_DIR/lib/profiles.sh"
  mock_reset

  FAKE_BIN="$(mktemp -d)"
  export PATH="${FAKE_BIN}:${PATH}"
}

teardown() {
  rm -rf "${FAKE_BIN}"
}

@test "profiles: invalid profile exits with code 1 and lists available profiles" {
  run resolve_profile "invalid-profile-xyz" "false"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: Unknown profile 'invalid-profile-xyz'"* ]]
  [[ "$output" == *"Available profiles:"* ]]
  [[ "$output" == *"server"* ]]
  [[ "$output" == *"desktop-minimal"* ]]
  [[ "$output" == *"desktop-full"* ]]
  [[ "$output" == *"gaming"* ]]
}

@test "profiles: CLI archforge --profile=invalid exits with code 1" {
  run "$ARCHFORGE_DIR/archforge" --profile=bogus --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown profile 'bogus'"* ]]
}

@test "profiles: composition with --modules performs clean deduplication and respects MODULE_EXECUTION_ORDER" {
  # Server base + extra module vmware-host + duplicate pacman
  run resolve_profile "server" "true" "vmware-host" "pacman"
  [ "$status" -eq 0 ]

  # Expected: pacman should appear only once, and vmware-host should be last per MODULE_EXECUTION_ORDER
  local -a lines=("${lines[@]}")
  local pacman_count=0
  local mod
  for mod in "${lines[@]}"; do
    if [[ "${mod}" == "pacman" ]]; then
      pacman_count=$(( pacman_count + 1 ))
    fi
  done
  [ "${pacman_count}" -eq 1 ]

  # Last element should be vmware-host
  local last_idx=$(( ${#lines[@]} - 1 ))
  [ "${lines[last_idx]}" = "vmware-host" ]
}

@test "profiles: --no-hardware-detect prevents adding GPU, laptop, and sensor modules" {
  # Simulate dual GPU (AMD+NVIDIA) and laptop battery
  cat > "${FAKE_BIN}/lspci" <<'LSPCI_EOF'
#!/usr/bin/env bash
echo "00:02.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Cezanne [Radeon Vega Series / Radeon Vega Mobile Series] (rev c5)"
echo "01:00.0 VGA compatible controller: NVIDIA Corporation GA106M [GeForce RTX 3060 Mobile / Max-Q] (rev a1)"
LSPCI_EOF
  chmod +x "${FAKE_BIN}/lspci"
  export IS_LAPTOP=true

  run resolve_profile "desktop-minimal" "true"
  [ "$status" -eq 0 ]
  [[ "$output" != *"amd"* ]]
  [[ "$output" != *"nvidia"* ]]
  [[ "$output" != *"tlp"* ]]
  [[ "$output" != *"acpid"* ]]
  [[ "$output" != *"sensors"* ]]
}

@test "profiles: auto-hardware-detect adds AMD GPU when AMD is present" {
  cat > "${FAKE_BIN}/lspci" <<'LSPCI_EOF'
#!/usr/bin/env bash
echo "03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX 6700/6750 XT]"
LSPCI_EOF
  chmod +x "${FAKE_BIN}/lspci"
  export IS_LAPTOP=false ARCHFORGE_IS_VM=true

  run resolve_profile "desktop-minimal" "false"
  [ "$status" -eq 0 ]
  [[ "$output" == *"amd"* ]]
  [[ "$output" != *"intel"* ]]
  [[ "$output" != *"nvidia"* ]]
}

@test "profiles: auto-hardware-detect adds Intel GPU when Intel is present" {
  cat > "${FAKE_BIN}/lspci" <<'LSPCI_EOF'
#!/usr/bin/env bash
echo "00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-S GT1 [UHD Graphics 770]"
LSPCI_EOF
  chmod +x "${FAKE_BIN}/lspci"
  export IS_LAPTOP=false ARCHFORGE_IS_VM=true

  run resolve_profile "desktop-minimal" "false"
  [ "$status" -eq 0 ]
  [[ "$output" == *"intel"* ]]
  [[ "$output" != *"amd"* ]]
  [[ "$output" != *"nvidia"* ]]
}

@test "profiles: auto-hardware-detect adds both AMD and NVIDIA on dual-GPU hybrid laptops" {
  cat > "${FAKE_BIN}/lspci" <<'LSPCI_EOF'
#!/usr/bin/env bash
echo "00:02.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Cezanne (rev c5)"
echo "01:00.0 3D controller: NVIDIA Corporation GA106M [GeForce RTX 3060 Mobile] (rev a1)"
LSPCI_EOF
  chmod +x "${FAKE_BIN}/lspci"
  export IS_LAPTOP=true ARCHFORGE_IS_VM=true

  run resolve_profile "desktop-full" "false"
  [ "$status" -eq 0 ]
  [[ "$output" == *"amd"* ]]
  [[ "$output" == *"nvidia"* ]]
  [[ "$output" == *"tlp"* ]]
  [[ "$output" == *"acpid"* ]]
}

@test "profiles: auto-hardware-detect includes sensors on bare-metal and omits on VM" {
  # Mock lspci to empty
  cat > "${FAKE_BIN}/lspci" <<'LSPCI_EOF'
#!/usr/bin/env bash
exit 0
LSPCI_EOF
  chmod +x "${FAKE_BIN}/lspci"

  # 1. On bare metal (ARCHFORGE_IS_VM=false)
  export ARCHFORGE_IS_VM=false IS_LAPTOP=false
  run resolve_profile "server" "false"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sensors"* ]]

  # 2. Inside VM (ARCHFORGE_IS_VM=true)
  export ARCHFORGE_IS_VM=true
  run resolve_profile "server" "false"
  [ "$status" -eq 0 ]
  [[ "$output" != *"sensors"* ]]
}

@test "profiles: gaming safeguard warns when --no-hardware-detect has no GPU in --modules" {
  export YES_FLAG=true DRY_RUN=true ARCHFORGE_TEST=true
  run resolve_profile "gaming" "true"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Profile 'gaming' selected with --no-hardware-detect and no GPU driver"* ]]
}

@test "profiles: non-interactivity --profile=desktop-full with --yes --dry-run completes cleanly" {
  run "$ARCHFORGE_DIR/archforge" --profile=desktop-full --yes --dry-run --no-hardware-detect
  [ "$status" -eq 0 ]
  [[ "$output" == *"Session Summary"* ]]
  [[ "$output" == *"PipeWire"* || "$output" == *"Audio"* ]]
  [[ "$output" == *"Bluetooth"* ]]
  [[ "$output" == *"Printing"* ]]
}
