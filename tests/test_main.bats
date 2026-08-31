#!/usr/bin/env bats
load 'setup'

@test "archforge --help exits 0 and shows Usage" {
  run "$ARCHFORGE_DIR/archforge" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "archforge --version exits 0" {
  run "$ARCHFORGE_DIR/archforge" --version
  [ "$status" -eq 0 ]
}

@test "parse_args sets DRY_RUN=true for --dry-run" {
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/archforge" --parse-only
  DRY_RUN=false
  parse_args --dry-run
  [[ "$DRY_RUN" == "true" ]]
}

@test "parse_args sets YES_FLAG=true for --yes" {
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/archforge" --parse-only
  YES_FLAG=false
  parse_args --yes
  [[ "$YES_FLAG" == "true" ]]
}

@test "parse_args sets REQUESTED_MODULES from --modules" {
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/archforge" --parse-only
  parse_args --modules=dns,firewall
  [[ "${REQUESTED_MODULES[0]}" == "dns" ]]
  [[ "${REQUESTED_MODULES[1]}" == "firewall" ]]
}

# M-1 regression: whitespace around comma-separated --modules tokens must be
# trimmed. Previously "pacman, firewall , dns" produced " firewall " (with
# spaces baked in), which _find_module_file() would never match, silently
# failing that module with "Module not found: firewall ".
@test "parse_args trims whitespace around --modules tokens" {
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/archforge" --parse-only
  parse_args --modules="pacman, firewall , dns"
  [[ "${REQUESTED_MODULES[0]}" == "pacman" ]]
  [[ "${REQUESTED_MODULES[1]}" == "firewall" ]]
  [[ "${REQUESTED_MODULES[2]}" == "dns" ]]
}

@test "parse_args --modules with empty string still yields an empty array" {
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/archforge" --parse-only
  parse_args --modules=""
  [ "${#REQUESTED_MODULES[@]}" -eq 0 ]
}

@test "_find_module_file returns path for known module id" {
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/archforge" --parse-only
  result="$(_find_module_file dns)"
  [[ "$result" == *"03-security/dns.sh" ]]
}

@test "_find_module_file returns non-zero for unknown module" {
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/archforge" --parse-only
  run _find_module_file "no-such-module-$$"
  [ "$status" -ne 0 ]
}
