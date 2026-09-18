#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true DRY_RUN=false YES_FLAG=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  source "$ARCHFORGE_DIR/modules/02-system-services/users-groups.sh"
  mock_reset
}

@test "users-groups module_info exposes metadata and official ArchWiki sources" {
  module_info
  [ -n "${MODULE_NAME}" ]
  [[ "${MODULE_WIKI_SOURCE}" == *"aur-wiki-user-and-groups.txt"* ]]
}

@test "users-groups adheres to ArchWiki by never offering deprecated pre-systemd groups" {
  # ArchWiki: Users and groups#Pre-systemd groups
  run grep -E '"(audio|video|storage|optical|scanner|games)\|' "$ARCHFORGE_DIR/modules/02-system-services/users-groups.sh"
  [ "$status" -ne 0 ]
}

@test "users-groups adds user to present system groups" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/getent" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "group" && ("$2" == "wheel" || "$2" == "lp") ]]; then
  exit 0
fi
exit 1
EOF
  cat > "${fake_bin}/id" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-Gn" ]]; then
  echo "users"
  exit 0
fi
exit 0
EOF
  chmod +x "${fake_bin}/getent" "${fake_bin}/id"

  PATH="${fake_bin}:${PATH}" run module_run
  [ "$status" -eq 0 ]
  mock_ran "sudo usermod -aG wheel"
  mock_ran "sudo usermod -aG lp"

  rm -rf "${fake_bin}"
}

@test "users-groups skips groups that do not exist on the system" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/getent" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  cat > "${fake_bin}/id" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/getent" "${fake_bin}/id"

  PATH="${fake_bin}:${PATH}" run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Group 'wheel' not found — skipping"* ]]
  [[ "$output" == *"Group 'docker' not found — skipping"* ]]

  rm -rf "${fake_bin}"
}

@test "users-groups skips groups the user is already a member of" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/getent" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${fake_bin}/id" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-Gn" ]]; then
  echo "users wheel docker"
  exit 0
fi
exit 0
EOF
  chmod +x "${fake_bin}/getent" "${fake_bin}/id"

  PATH="${fake_bin}:${PATH}" run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"already in wheel"* ]]
  [[ "$output" == *"already in docker"* ]]
  run cat "${MOCK_LOG_FILE}"
  [[ "$output" != *"usermod -aG wheel"* ]]
  [[ "$output" != *"usermod -aG docker"* ]]

  rm -rf "${fake_bin}"
}

@test "users-groups warns about docker root-equivalent privileges" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/getent" <<'EOF'
#!/usr/bin/env bash
if [[ "$2" == "docker" ]]; then exit 0; fi
exit 1
EOF
  cat > "${fake_bin}/id" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-Gn" ]]; then echo "users"; exit 0; fi
exit 0
EOF
  chmod +x "${fake_bin}/getent" "${fake_bin}/id"

  PATH="${fake_bin}:${PATH}" run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker group grants root-equivalent access"* ]]
  mock_ran "sudo usermod -aG docker"

  rm -rf "${fake_bin}"
}

@test "users-groups handles non-existent custom username cleanly" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/id" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${fake_bin}/id"

  export YES_FLAG=false
  run bash -c "printf 'n\nnonexistentuser_xyz\n' | ( export PATH='${fake_bin}:'\"\$PATH\" ARCHFORGE_DIR='$ARCHFORGE_DIR' ARCHFORGE_TEST=true YES_FLAG=false; source '$ARCHFORGE_DIR/lib/core.sh'; source '$ARCHFORGE_DIR/modules/02-system-services/users-groups.sh'; module_run )"
  [ "$status" -ne 0 ]
  [[ "$output" == *"User 'nonexistentuser_xyz' not found on this system"* ]]

  rm -rf "${fake_bin}"
}
