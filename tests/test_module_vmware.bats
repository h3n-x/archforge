#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true DRY_RUN=false YES_FLAG=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  mock_reset
}

@test "vmware-host module_info has MODULE_WIKI_SOURCE" {
  source "$ARCHFORGE_DIR/modules/13-virtualization/vmware-host.sh"
  module_info
  [[ -n "${MODULE_WIKI_SOURCE}" ]]
}

# H-4 regression: vmware-hostd.service was removed in VMware Workstation 16+
# (confirmed by aur-wiki-vmware.txt: "vmware-hostd.service for sharing
# virtual machines (not available since version 16)"). Enabling it
# unconditionally under `set -e` aborted the whole module on any modern
# install. This machine has no `systemctl` at all, which is the same
# "unit absent" outcome the guard must handle gracefully.
@test "vmware-host module_run completes without aborting when vmware-hostd.service is absent (H-4)" {
  source "$ARCHFORGE_DIR/modules/13-virtualization/vmware-host.sh"
  run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"vmware-hostd.service not present"* ]]
  [[ "$output" == *"VMware Workstation installed."* ]]
}

@test "vmware-host module_run enables vmware-hostd.service when the unit is present" {
  # Fake systemctl reporting vmware-hostd.service as a known unit.
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "list-unit-files" && "$2" == "vmware-hostd.service" ]] && exit 0
exit 1
EOF
  chmod +x "${fake_bin}/systemctl"
  export PATH="${fake_bin}:${PATH}"

  source "$ARCHFORGE_DIR/modules/13-virtualization/vmware-host.sh"
  run module_run

  [ "$status" -eq 0 ]
  [[ "$output" != *"vmware-hostd.service not present"* ]]
  mock_ran "systemctl enable --now vmware-hostd.service"

  rm -rf "${fake_bin}"
}
