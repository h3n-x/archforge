#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true YES_FLAG=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  mock_reset

  # Fake lspci reporting an Ampere-family NVIDIA GPU (RTX 3060-class device
  # id 10de:2204), so _detect_nvidia_family() succeeds without falling back
  # to the interactive manual-selection prompt.
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

@test "nvidia module_info has MODULE_WIKI_SOURCE" {
  source "$ARCHFORGE_DIR/modules/10-graphics/nvidia.sh"
  module_info
  [[ -n "${MODULE_WIKI_SOURCE}" ]]
}

# H-6 regression: a laptop with a non-hybrid NVIDIA GPU (DETECTED_GPU=NVIDIA,
# not "Multiple (...)") must NOT auto-configure Optimus/EnvyControl. Before
# the fix, IS_LAPTOP alone triggered Optimus setup regardless of whether the
# system actually has a second (integrated) GPU.
@test "nvidia module_run skips Optimus on a laptop without hybrid graphics (H-6)" {
  export DRY_RUN=true DETECTED_GPU="NVIDIA" IS_LAPTOP=true
  source "$ARCHFORGE_DIR/modules/10-graphics/nvidia.sh"
  run module_run
  [[ "$output" == *"no hybrid graphics found"* ]]
  [[ "$output" != *"envycontrol"* ]]
}

# H-6 regression: a laptop WITH hybrid graphics (DETECTED_GPU reads
# "Multiple (...)" per lib/detect.sh) must still configure Optimus as before
# -- this proves the fix didn't just disable Optimus outright.
@test "nvidia module_run configures Optimus on a laptop with hybrid graphics (H-6)" {
  export DRY_RUN=true DETECTED_GPU="Multiple (NVIDIA)" IS_LAPTOP=true
  source "$ARCHFORGE_DIR/modules/10-graphics/nvidia.sh"
  run module_run
  [[ "$output" == *"envycontrol -s hybrid"* ]]
}

# H-5 regression: with no AUR helper configured, a DKMS-only driver install
# must abort with a clear error instead of silently reporting success while
# nothing was actually installed. aur_install() no-ops (log_skip, exit 0)
# when AUR_HELPER is empty -- without the pkg_installed() verification this
# added, the module would proceed straight to "NVIDIA driver installed."
#
# Caveat: this scenario also exercises a separate, pre-existing bug in
# _select_nvidia_driver() (untouched by Phase 3) where log_info()/log_warn()
# output leaks into the $driver value via command substitution, for every
# GPU family except ada/ampere/turing under --yes/--dry-run. That bug garbles
# the driver name shown in this test's error output but does not affect the
# assertions below, which only check the final outcome.
@test "nvidia module_run aborts without a false-success message when no AUR helper is available for a DKMS-only driver (H-5)" {
  export DRY_RUN=false ARCHFORGE_TEST=false AUR_HELPER=""
  export DETECTED_GPU="NVIDIA" IS_LAPTOP=false
  # Pascal-family device id (GTX 1070-class) -> nvidia-580xx-dkms, AUR-only.
  cat > "${FAKE_BIN}/lspci" <<'LSPCI_EOF'
#!/usr/bin/env bash
echo "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation Device [10de:1b81] (rev a1)"
LSPCI_EOF
  chmod +x "${FAKE_BIN}/lspci"

  source "$ARCHFORGE_DIR/modules/10-graphics/nvidia.sh"
  run module_run

  [ "$status" -ne 0 ]
  [[ "$output" != *"NVIDIA driver installed"* ]]
  [[ "$output" == *"was not installed"* ]]
}
