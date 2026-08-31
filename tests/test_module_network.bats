#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true DRY_RUN=true YES_FLAG=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  source "$ARCHFORGE_DIR/modules/05-networking/network.sh"
  mock_reset
}

@test "network module_info has MODULE_WIKI_SOURCE" {
  module_info
  [[ -n "${MODULE_WIKI_SOURCE}" ]]
}

# H-8 regression: custom /etc/hosts entries (VPN hosts, docker, ad-block
# lists, comments, etc.) must survive unchanged. Previously the module fully
# overwrote /etc/hosts with only the 3 standard lines, discarding everything
# else.
@test "_update_hosts_file preserves custom entries while updating the hostname line" {
  local tmp; tmp="$(mktemp)"
  cat > "${tmp}" <<'EOF'
127.0.0.1	localhost
::1		localhost
127.0.1.1	old-hostname.localdomain old-hostname

# Custom entries
10.8.0.1	vpn-gateway
172.17.0.2	my-docker-container
0.0.0.0 ads.example.com
EOF
  run _update_hosts_file "${tmp}" "new-hostname"
  [[ "$output" == *"127.0.1.1   new-hostname.localdomain new-hostname"* ]]
  [[ "$output" == *"vpn-gateway"* ]]
  [[ "$output" == *"my-docker-container"* ]]
  [[ "$output" == *"ads.example.com"* ]]
  [[ "$output" == *"# Custom entries"* ]]
  rm -f "${tmp}"
}

@test "_update_hosts_file appends the 3 standard lines when a minimal/custom-only file has none of them" {
  local tmp; tmp="$(mktemp)"
  echo "10.0.0.5	some-custom-entry" > "${tmp}"
  run _update_hosts_file "${tmp}" "myhost"
  [[ "$output" == *"some-custom-entry"* ]]
  [[ "$output" == *"127.0.0.1   localhost"* ]]
  [[ "$output" == *"::1         localhost"* ]]
  [[ "$output" == *"127.0.1.1   myhost.localdomain myhost"* ]]
  rm -f "${tmp}"
}

@test "_update_hosts_file does not error on a non-existent file" {
  run _update_hosts_file "/tmp/archforge-does-not-exist-hosts-$$" "myhost"
  [ "$status" -eq 0 ]
  [[ "$output" == *"127.0.1.1   myhost.localdomain myhost"* ]]
}

@test "_update_hosts_file is idempotent when run twice on its own output" {
  local tmp tmp2; tmp="$(mktemp)"; tmp2="$(mktemp)"
  cat > "${tmp}" <<'EOF'
127.0.0.1	localhost
::1		localhost
127.0.1.1	myhost.localdomain myhost
10.8.0.1	vpn-gateway
EOF
  _update_hosts_file "${tmp}" "myhost" > "${tmp2}"
  run _update_hosts_file "${tmp2}" "myhost"
  local second_count
  second_count="$(echo "$output" | grep -c '^127\.0\.1\.1')"
  [ "${second_count}" -eq 1 ]
  [[ "$output" == *"vpn-gateway"* ]]
  rm -f "${tmp}" "${tmp2}"
}
