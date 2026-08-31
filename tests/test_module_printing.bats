#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true DRY_RUN=true YES_FLAG=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  source "$ARCHFORGE_DIR/modules/12-peripherals/printing.sh"
  mock_reset
}

@test "printing module_info has MODULE_WIKI_SOURCE" {
  module_info
  [[ -n "${MODULE_WIKI_SOURCE}" ]]
}

@test "printing module_run in dry-run mode exits 0" {
  run module_run
  [ "$status" -eq 0 ]
}

# M-2 regression: mdns_minimal must be inserted before "resolve", matching
# the exact ArchWiki example (aur-wiki-avahi.txt). The previous greedy regex
# `s/\(hosts:.*\)\(resolve\|dns\)/.../` inserted it before the LAST match
# ("dns") instead, landing after "resolve" -- confirmed wrong per the wiki.
@test "_insert_mdns_minimal matches the exact ArchWiki example line" {
  local tmp; tmp="$(mktemp)"
  echo "hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns" > "${tmp}"
  run _insert_mdns_minimal "${tmp}"
  [[ "$output" == "hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns" ]]
  rm -f "${tmp}"
}

@test "_insert_mdns_minimal falls back to before 'dns' when 'resolve' is absent" {
  local tmp; tmp="$(mktemp)"
  echo "hosts: files myhostname dns" > "${tmp}"
  run _insert_mdns_minimal "${tmp}"
  [[ "$output" == "hosts: files myhostname mdns_minimal [NOTFOUND=return] dns" ]]
  rm -f "${tmp}"
}

@test "_insert_mdns_minimal inserts before 'resolve' even when 'dns' also appears later on the line" {
  local tmp; tmp="$(mktemp)"
  echo "hosts: files resolve [!UNAVAIL=return] dns" > "${tmp}"
  run _insert_mdns_minimal "${tmp}"
  [[ "$output" == "hosts: files mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] dns" ]]
  rm -f "${tmp}"
}

@test "_insert_mdns_minimal appends to the end when neither 'resolve' nor 'dns' is present" {
  local tmp; tmp="$(mktemp)"
  echo "hosts: files" > "${tmp}"
  run _insert_mdns_minimal "${tmp}"
  [[ "$output" == "hosts: files mdns_minimal [NOTFOUND=return]" ]]
  rm -f "${tmp}"
}

@test "_insert_mdns_minimal leaves non-'hosts:' lines untouched" {
  local tmp; tmp="$(mktemp)"
  printf 'passwd: files systemd\nhosts: files dns\ngroup: files systemd\n' > "${tmp}"
  run _insert_mdns_minimal "${tmp}"
  [[ "$output" == "$(printf 'passwd: files systemd\nhosts: files mdns_minimal [NOTFOUND=return] dns\ngroup: files systemd')" ]]
  rm -f "${tmp}"
}
