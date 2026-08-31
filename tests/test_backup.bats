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
