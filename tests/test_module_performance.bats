#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true DRY_RUN=true YES_FLAG=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  mock_reset
}

@test "performance module_info has MODULE_WIKI_SOURCE" {
  source "$ARCHFORGE_DIR/modules/07-optimization/performance.sh"
  module_info
  [[ -n "${MODULE_WIKI_SOURCE}" ]]
}

@test "performance module_run in dry-run mode exits 0" {
  source "$ARCHFORGE_DIR/modules/07-optimization/performance.sh"
  run module_run
  [ "$status" -eq 0 ]
}

# Regression test for the C-1 finding (ARCHFORGE AUDIT, Phase 0):
# _configure_thp() used to write directly to
# /sys/kernel/mm/transparent_hugepage/{enabled,defrag} via a raw `sudo tee`,
# gated only by ARCHFORGE_TEST and NOT by DRY_RUN -- meaning `--dry-run`
# actually mutated live kernel state. This test proves that under DRY_RUN,
# `sudo` is never invoked for real: a fake `sudo` shim is placed first on
# PATH that leaves a marker file if it is ever actually executed.
#
# Caveat (UNCERTAIN on such a machine): if /etc/tmpfiles.d/archforge-thp.conf
# already exists on the machine running this test (e.g. archforge was run
# for real there before), _configure_thp() short-circuits before reaching the
# THP write and this test passes trivially without exercising the fixed code
# path. The static tests in test_static_safety.bats are the authoritative,
# environment-independent check for this class of bug.
@test "performance _configure_thp never invokes a real sudo under DRY_RUN (C-1 regression)" {
  export DRY_RUN=true ARCHFORGE_TEST=false
  source "$ARCHFORGE_DIR/modules/07-optimization/performance.sh"

  local fake_bin marker
  fake_bin="$(mktemp -d)"
  marker="$(mktemp -u)"
  cat > "${fake_bin}/sudo" <<SUDOEOF
#!/usr/bin/env bash
touch "${marker}"
exit 0
SUDOEOF
  chmod +x "${fake_bin}/sudo"

  PATH="${fake_bin}:${PATH}" run _configure_thp

  [ ! -e "${marker}" ]

  rm -rf "${fake_bin}"
  rm -f "${marker}"
}
