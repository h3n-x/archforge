#!/usr/bin/env bats
load 'setup'

setup() {
  source "$ARCHFORGE_DIR/lib/core.sh"
}

@test "log_ok outputs OK tag" {
  run log_ok "hello"
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"hello"* ]]
}

@test "log_error outputs ERROR tag" {
  run log_error "bad thing"
  [[ "$output" == *"ERROR"* ]]
}

@test "log_dry outputs DRYRUN tag" {
  run log_dry "would do X"
  [[ "$output" == *"DRYRUN"* ]]
}

@test "run_cmd executes in normal mode" {
  export DRY_RUN=false
  export ARCHFORGE_TEST=false
  run run_cmd echo "executed"
  [ "$status" -eq 0 ]
  [[ "$output" == *"executed"* ]]
}

@test "run_cmd skips execution in dry-run mode" {
  export DRY_RUN=true
  run run_cmd touch /tmp/archforge-should-not-exist-$$
  [ "$status" -eq 0 ]
  [ ! -f "/tmp/archforge-should-not-exist-$$" ]
  [[ "$output" == *"DRYRUN"* ]]
}

@test "run_cmd writes to MOCK_LOG_FILE in test mode" {
  export ARCHFORGE_TEST=true
  export DRY_RUN=false
  local tmp_log
  tmp_log="$(mktemp)"
  export MOCK_LOG_FILE="$tmp_log"
  run_cmd echo "mock-test-command"
  grep -qF "echo mock-test-command" "$tmp_log"
  rm -f "$tmp_log"
}

@test "run_cmd appends execution trace and stdout to LOG_FILE in non-test mode" {
  export ARCHFORGE_TEST=false
  export DRY_RUN=false
  local tmp_log
  tmp_log="$(mktemp)"
  export LOG_FILE="$tmp_log"

  run_cmd echo "stdout message to capture"

  grep -qF "[EXEC  ] echo stdout message to capture" "$tmp_log"
  grep -qF "stdout message to capture" "$tmp_log"
  rm -f "$tmp_log"
}

@test "run_cmd appends stderr to LOG_FILE and preserves exit code" {
  export ARCHFORGE_TEST=false
  export DRY_RUN=false
  local tmp_log
  tmp_log="$(mktemp)"
  export LOG_FILE="$tmp_log"

  run run_cmd bash -c 'echo "error stream output" >&2; exit 42'
  [ "$status" -eq 42 ]
  grep -qF "error stream output" "$tmp_log"
  rm -f "$tmp_log"
}


@test "confirm returns 0 when YES_FLAG is true" {
  export YES_FLAG=true
  run confirm "question?"
  [ "$status" -eq 0 ]
}

@test "confirm returns 0 when DRY_RUN is true" {
  export DRY_RUN=true
  run confirm "question?"
  [ "$status" -eq 0 ]
}

@test "validate_fstab passes for valid fstab with root mount" {
  local tmp
  tmp="$(mktemp)"
  echo "UUID=1234 / ext4 defaults,noatime 0 1" > "${tmp}"
  run validate_fstab "${tmp}"
  [ "$status" -eq 0 ]
  rm -f "${tmp}"
}

@test "validate_fstab fails when root mount is missing" {
  local tmp
  tmp="$(mktemp)"
  echo "UUID=1234 /home ext4 defaults 0 2" > "${tmp}"
  run validate_fstab "${tmp}"
  [ "$status" -ne 0 ]
  rm -f "${tmp}"
}

@test "validate_fstab fails for empty file" {
  local tmp
  tmp="$(mktemp)"
  run validate_fstab "${tmp}"
  [ "$status" -ne 0 ]
  rm -f "${tmp}"
}

@test "validate_nftables fails for empty file" {
  local tmp
  tmp="$(mktemp)"
  export ARCHFORGE_TEST=true
  run validate_nftables "${tmp}"
  [ "$status" -ne 0 ]
  rm -f "${tmp}"
}

@test "validate_nftables: path a - dry-run with cached sudo runs non-interactively and passes" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/nft" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${fake_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-n" ]]; then shift; exec "$@"; fi
exec "$@"
EOF
  chmod +x "${fake_bin}/nft" "${fake_bin}/sudo"

  local tmp; tmp="$(mktemp)"
  echo "table inet filter { chain input { type filter hook input priority 0; } }" > "${tmp}"

  PATH="${fake_bin}:${PATH}" ARCHFORGE_TEST=false DRY_RUN=true run validate_nftables "${tmp}"
  [ "$status" -eq 0 ]

  rm -rf "${fake_bin}" "${tmp}"
}

@test "validate_nftables: path b - dry-run without cached sudo skips privileged check with log_dry" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/nft" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${fake_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 1; fi
if [[ "$1" == "-n" ]]; then exit 1; fi
echo "UNEXPECTED PROMPT" >&2
exit 1
EOF
  chmod +x "${fake_bin}/nft" "${fake_bin}/sudo"

  local tmp; tmp="$(mktemp)"
  echo "table inet filter { chain input { type filter hook input priority 0; } }" > "${tmp}"

  PATH="${fake_bin}:${PATH}" ARCHFORGE_TEST=false DRY_RUN=true run validate_nftables "${tmp}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "skipped privileged nft syntax check" ]]
  [[ "$output" != *"UNEXPECTED PROMPT"* ]]

  rm -rf "${fake_bin}" "${tmp}"
}

@test "validate_nftables: path c - real mode without cached sudo and without TTY fails cleanly" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/nft" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${fake_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 1; fi
if [[ "$1" == "-n" ]]; then exit 1; fi
echo "UNEXPECTED INTERACTIVE PROMPT" >&2
exit 1
EOF
  chmod +x "${fake_bin}/nft" "${fake_bin}/sudo"

  local tmp; tmp="$(mktemp)"
  echo "table inet filter { chain input { type filter hook input priority 0; } }" > "${tmp}"

  PATH="${fake_bin}:${PATH}" ARCHFORGE_TEST=false DRY_RUN=false run validate_nftables "${tmp}" < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" =~ "requires sudo privileges, but no active sudo session is available" ]]
  [[ "$output" != *"UNEXPECTED INTERACTIVE PROMPT"* ]]

  rm -rf "${fake_bin}" "${tmp}"
}

@test "validate_nftables: path d - real mode with cached sudo validates ruleset without prompt" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/nft" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${fake_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-n" ]]; then shift; exec "$@"; fi
exec "$@"
EOF
  chmod +x "${fake_bin}/nft" "${fake_bin}/sudo"

  local tmp; tmp="$(mktemp)"
  echo "table inet filter { chain input { type filter hook input priority 0; } }" > "${tmp}"

  PATH="${fake_bin}:${PATH}" ARCHFORGE_TEST=false DRY_RUN=false run validate_nftables "${tmp}"
  [ "$status" -eq 0 ]

  rm -rf "${fake_bin}" "${tmp}"
}
