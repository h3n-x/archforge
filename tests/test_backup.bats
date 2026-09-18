#!/usr/bin/env bats
load 'setup'

setup() {
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  export SESSION_ID="2099-01-01_120000"
  export BACKUP_BASE_DIR="/tmp/archforge-bats-backup-$$"
  mkdir -p "$BACKUP_BASE_DIR"
  # Create a test file to back up
  echo "original content" > /tmp/archforge-test-file-$$
}

teardown() {
  rm -rf "$BACKUP_BASE_DIR" /tmp/archforge-test-file-$$ /tmp/archforge-restore-src-$$
}

@test "backup_file copies regular file to session backup dir" {
  backup_file "/tmp/archforge-test-file-$$"
  local dest="${BACKUP_BASE_DIR}/${SESSION_ID}/tmp/archforge-test-file-$$"
  [ -f "$dest" ]
  run cat "$dest"
  [[ "$output" == "original content" ]]
}

@test "backup_file writes FILE entry to session.manifest" {
  backup_file "/tmp/archforge-test-file-$$"
  local manifest="${BACKUP_BASE_DIR}/${SESSION_ID}/session.manifest"
  [ -f "$manifest" ]
  run grep "TYPE=file" "$manifest"
  [ "$status" -eq 0 ]
}

@test "backup_file records MODE in manifest" {
  backup_file "/tmp/archforge-test-file-$$"
  local manifest="${BACKUP_BASE_DIR}/${SESSION_ID}/session.manifest"
  run grep "MODE=" "$manifest"
  [ "$status" -eq 0 ]
}

@test "backup_file handles symlink without dereferencing" {
  ln -sf /tmp/archforge-test-file-$$ /tmp/archforge-test-link-$$
  backup_file "/tmp/archforge-test-link-$$"
  local manifest="${BACKUP_BASE_DIR}/${SESSION_ID}/session.manifest"
  run grep "TYPE=symlink" "$manifest"
  [ "$status" -eq 0 ]
  rm -f /tmp/archforge-test-link-$$
}

@test "backup_file skips non-existent file with warning" {
  run backup_file "/tmp/does-not-exist-archforge-test-$$"
  [ "$status" -eq 0 ]
}

@test "backup_file records path in MOCK_BACKUP_LOG in test mode" {
  mock_reset
  backup_file "/tmp/archforge-test-file-$$"
  mock_backed_up "/tmp/archforge-test-file-$$"
}

@test "record_attr writes ATTR entry to manifest" {
  record_attr "/tmp/archforge-test-file-$$"
  local manifest="${BACKUP_BASE_DIR}/${SESSION_ID}/session.manifest"
  run grep "ATTR_PATH=/tmp/archforge-test-file-$$" "$manifest"
  [ "$status" -eq 0 ]
}

@test "list_sessions prints 'No backup sessions found' when base dir missing" {
  export BACKUP_BASE_DIR="/tmp/no-such-dir-archforge-$$"
  run list_sessions
  [ "$status" -eq 0 ]
  [[ "$output" == *"No backup sessions found"* ]]
}

@test "_restore_full restores a backed-up file" {
  # Set up: backup a real file
  echo "original content" > /tmp/archforge-restore-src-$$
  backup_file "/tmp/archforge-restore-src-$$"

  # Modify the source file
  echo "modified content" > /tmp/archforge-restore-src-$$

  # Restore it (disable test mode so run_cmd actually executes)
  export YES_FLAG=true
  export ARCHFORGE_TEST=false
  local session_dir="${BACKUP_BASE_DIR}/${SESSION_ID}"
  local manifest="${session_dir}/session.manifest"
  _restore_full "${session_dir}" "${manifest}"
  export ARCHFORGE_TEST=true

  # Verify original content restored
  run cat /tmp/archforge-restore-src-$$
  [ "$status" -eq 0 ]
  [[ "$output" == "original content" ]]

  # Cleanup
  rm -f /tmp/archforge-restore-src-$$
}

# ── Phase 2: Model B — restore can undo file creation, not just overwrites ──

@test "backup_file records TYPE=created for a not-yet-existing path" {
  local newpath="/tmp/archforge-test-created-$$"
  rm -f "$newpath"
  backup_file "$newpath"
  local manifest="${BACKUP_BASE_DIR}/${SESSION_ID}/session.manifest"
  run grep "PATH=${newpath}  TYPE=created" "$manifest"
  [ "$status" -eq 0 ]
}

@test "backup_file does not copy any content for a not-yet-existing path" {
  local newpath="/tmp/archforge-test-created2-$$"
  rm -f "$newpath"
  backup_file "$newpath"
  local dest="${BACKUP_BASE_DIR}/${SESSION_ID}${newpath}"
  [ ! -e "$dest" ]
}

@test "backup_file records path in MOCK_BACKUP_LOG for a not-yet-existing path too" {
  mock_reset
  local newpath="/tmp/archforge-test-created3-$$"
  rm -f "$newpath"
  backup_file "$newpath"
  mock_backed_up "$newpath"
}

@test "_restore_full removes a file that archforge created (Model B)" {
  local created_path="/tmp/archforge-test-created-restore-$$"
  rm -f "$created_path"
  backup_file "$created_path"
  # Simulate the module actually creating the file after backup_file()
  # recorded the TYPE=created intent.
  echo "new content" > "$created_path"

  export YES_FLAG=true
  export ARCHFORGE_TEST=false
  local session_dir="${BACKUP_BASE_DIR}/${SESSION_ID}"
  local manifest="${session_dir}/session.manifest"
  _restore_full "${session_dir}" "${manifest}"
  export ARCHFORGE_TEST=true

  [ ! -e "$created_path" ]
}

@test "_restore_full is a no-op (no error) when a created-file entry's target is already absent" {
  # Simulates a crash between backup_file() recording TYPE=created and the
  # module actually writing the file: the manifest says "created" but the
  # path never came into existence. restore must not error out on this.
  local created_path="/tmp/archforge-test-created-absent-$$"
  rm -f "$created_path"
  backup_file "$created_path"

  export YES_FLAG=true
  export ARCHFORGE_TEST=false
  local session_dir="${BACKUP_BASE_DIR}/${SESSION_ID}"
  local manifest="${session_dir}/session.manifest"
  run _restore_full "${session_dir}" "${manifest}"
  export ARCHFORGE_TEST=true

  [ "$status" -eq 0 ]
  [ ! -e "$created_path" ]
}

@test "_restore_full remains backward compatible with a pre-Phase-2 manifest (no TYPE=created entries)" {
  # Hand-writes a manifest in the exact format used before Model B existed
  # (only TYPE=file / TYPE=symlink entries) to prove old backup sessions
  # still restore correctly with the new _restore_entry() code.
  local old_path="/tmp/archforge-test-oldformat-$$"
  echo "original" > "$old_path"

  local session_dir="${BACKUP_BASE_DIR}/${SESSION_ID}"
  local relative="${old_path#/}"
  mkdir -p "${session_dir}/${relative%/*}"
  cp -p "$old_path" "${session_dir}/${relative}"

  local manifest="${session_dir}/session.manifest"
  {
    echo "DATE=${SESSION_ID}"
    echo "SESSION_ID=${SESSION_ID}"
    echo "MODULES_MODIFIED="
    echo "FILES:"
    echo "  PATH=${old_path}  TYPE=file  MODE=644  OWNER=$(id -un):$(id -gn)  WAS_CREATED=false"
    echo "ATTRS:"
  } > "$manifest"

  echo "modified" > "$old_path"

  export YES_FLAG=true
  export ARCHFORGE_TEST=false
  _restore_full "${session_dir}" "${manifest}"
  export ARCHFORGE_TEST=true

  run cat "$old_path"
  [[ "$output" == "original" ]]

  rm -f "$old_path"
}

@test "_needs_root_for_path detects unwritable destination" {
  if [[ "${EUID}" -ne 0 ]]; then
    run _needs_root_for_path "/etc/archforge-unwritable-test-file"
    [ "$status" -eq 0 ]
  fi
}

@test "_get_default_backup_base uses user home under SUDO_USER" {
  local cur_user; cur_user="$(id -un)"
  export SUDO_USER="${cur_user}"
  unset BACKUP_BASE_DIR
  local base; base="$(_get_default_backup_base)"
  [[ "${base}" == *"${cur_user}/.local/share/archforge/backups" ]]
}

@test "backup_file in DRY_RUN does not write file to disk" {
  export DRY_RUN=true ARCHFORGE_TEST=false
  export BACKUP_BASE_DIR="/tmp/archforge-dryrun-base-$$"
  export SESSION_ID="dryrun-session-1"
  local test_file="/tmp/archforge-dryrun-src-$$"
  echo "content" > "${test_file}"

  backup_file "${test_file}"
  local copied="${BACKUP_BASE_DIR}/${SESSION_ID}${test_file}"
  [ ! -f "${copied}" ]

  rm -rf "${BACKUP_BASE_DIR}" "${test_file}"
}

# ── Module tagging and granular restore tests ─────────────────────────────────

@test "backup_file records CURRENT_MODULE in manifest and updates MODULES_MODIFIED" {
  export CURRENT_MODULE="dns"
  backup_file "/tmp/archforge-test-file-$$"
  local manifest="${BACKUP_BASE_DIR}/${SESSION_ID}/session.manifest"

  run grep "^MODULES_MODIFIED=dns" "$manifest"
  [ "$status" -eq 0 ]

  run grep "PATH=/tmp/archforge-test-file-$$" "$manifest"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODULE=dns"* ]]
  unset CURRENT_MODULE
}

@test "backup_file infers module from caller script when CURRENT_MODULE is unset" {
  unset CURRENT_MODULE
  local dummy_script="/tmp/firewall.sh"
  cat <<EOF > "$dummy_script"
source "$ARCHFORGE_DIR/lib/core.sh"
source "$ARCHFORGE_DIR/lib/backup.sh"
export BACKUP_BASE_DIR="$BACKUP_BASE_DIR"
export SESSION_ID="$SESSION_ID"
backup_file "/tmp/archforge-test-file-$$"
EOF
  chmod +x "$dummy_script"
  bash "$dummy_script"
  rm -f "$dummy_script"

  local manifest="${BACKUP_BASE_DIR}/${SESSION_ID}/session.manifest"
  run grep "^MODULES_MODIFIED=firewall" "$manifest"
  [ "$status" -eq 0 ]
  run grep "MODULE=firewall" "$manifest"
  [ "$status" -eq 0 ]
}

@test "_restore_module restores only files belonging to target module" {
  local file_a="/tmp/archforge-test-mod-a-$$"
  local file_b="/tmp/archforge-test-mod-b-$$"
  echo "original A" > "$file_a"
  echo "original B" > "$file_b"

  CURRENT_MODULE="mod_a" backup_file "$file_a"
  CURRENT_MODULE="mod_b" backup_file "$file_b"
  unset CURRENT_MODULE

  # Modify both files
  echo "modified A" > "$file_a"
  echo "modified B" > "$file_b"

  export YES_FLAG=true
  export ARCHFORGE_TEST=false
  local session_dir="${BACKUP_BASE_DIR}/${SESSION_ID}"
  local manifest="${session_dir}/session.manifest"

  # Restore only mod_a
  _restore_module "${session_dir}" "${manifest}" "mod_a"
  export ARCHFORGE_TEST=true

  # Verify file_a is restored, but file_b is NOT restored
  run cat "$file_a"
  [[ "$output" == "original A" ]]

  run cat "$file_b"
  [[ "$output" == "modified B" ]]

  rm -f "$file_a" "$file_b"
}

@test "_restore_module warns and returns non-zero if target module has no files" {
  export CURRENT_MODULE="mod_a"
  backup_file "/tmp/archforge-test-file-$$"
  unset CURRENT_MODULE

  local session_dir="${BACKUP_BASE_DIR}/${SESSION_ID}"
  local manifest="${session_dir}/session.manifest"

  run _restore_module "${session_dir}" "${manifest}" "nonexistent_mod"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No files recorded for module 'nonexistent_mod'"* ]]
}

@test "restore_session with target_session and target_module restores directly without prompt" {
  local file_c="/tmp/archforge-test-mod-c-$$"
  echo "original C" > "$file_c"

  CURRENT_MODULE="mod_c" backup_file "$file_c"
  unset CURRENT_MODULE

  echo "modified C" > "$file_c"

  export YES_FLAG=true
  export ARCHFORGE_TEST=false
  run restore_session "${SESSION_ID}" "mod_c"
  export ARCHFORGE_TEST=true

  [ "$status" -eq 0 ]
  run cat "$file_c"
  [[ "$output" == "original C" ]]

  rm -f "$file_c"
}

@test "_restore_full restores all file types from a new manifest containing MODULE= tags" {
  local reg_file="/tmp/archforge-test-full-reg-$$"
  local sym_file="/tmp/archforge-test-full-sym-$$"
  local sym_target="/tmp/archforge-test-full-target-$$"
  local cre_file="/tmp/archforge-test-full-cre-$$"

  # Setup regular file
  echo "original full content" > "$reg_file"
  CURRENT_MODULE="dns" backup_file "$reg_file"
  echo "modified full content" > "$reg_file"

  # Setup symlink
  echo "target content" > "$sym_target"
  ln -sf "$sym_target" "$sym_file"
  CURRENT_MODULE="network" backup_file "$sym_file"
  rm -f "$sym_file"
  echo "wrong target" > "$sym_file"

  # Setup created file (did not exist before backup)
  rm -f "$cre_file"
  CURRENT_MODULE="firewall" backup_file "$cre_file"
  echo "created content that should be removed" > "$cre_file"

  local session_dir="${BACKUP_BASE_DIR}/${SESSION_ID}"
  local manifest="${session_dir}/session.manifest"

  # Verify that all 3 lines in the manifest have MODULE= tags
  run grep "MODULE=dns" "$manifest"
  [ "$status" -eq 0 ]
  run grep "MODULE=network" "$manifest"
  [ "$status" -eq 0 ]
  run grep "MODULE=firewall" "$manifest"
  [ "$status" -eq 0 ]

  # Run full session restore
  export YES_FLAG=true
  export ARCHFORGE_TEST=false
  _restore_full "${session_dir}" "${manifest}"
  export ARCHFORGE_TEST=true

  # Assert 1: regular file content restored
  run cat "$reg_file"
  [[ "$output" == "original full content" ]]

  # Assert 2: symlink restored pointing to sym_target
  [ -L "$sym_file" ]
  run readlink "$sym_file"
  [[ "$output" == "$sym_target" ]]

  # Assert 3: created file removed
  [ ! -e "$cre_file" ]

  # Cleanup
  rm -f "$reg_file" "$sym_file" "$sym_target" "$cre_file"
}


