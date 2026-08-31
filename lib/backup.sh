#!/usr/bin/env bash
# lib/backup.sh — backup_file(), list_sessions(), restore_session()
# All state written to disk — safe across subshell boundaries.
# shellcheck shell=bash

_backup_dir() {
  # SESSION_ID is set by the caller (main entry point or test setup)
  # shellcheck disable=SC2154
  echo "${BACKUP_BASE_DIR:-${HOME}/.local/share/archforge/backups}/${SESSION_ID}"
}

_manifest_file() {
  local dir
  dir="$(_backup_dir)" || true
  echo "${dir}/session.manifest"
}

_ensure_manifest() {
  local manifest
  manifest="$(_manifest_file)" || true
  if [[ ! -f "${manifest}" ]]; then
    mkdir -p "$(dirname "${manifest}")"
    {
      echo "DATE=${SESSION_ID}"
      echo "SESSION_ID=${SESSION_ID}"
      echo "MODULES_MODIFIED="
      echo "FILES:"
      echo "ATTRS:"
    } > "${manifest}"
  fi
}

backup_file() {
  local path="$1"

  _ensure_manifest

  local session_dir
  session_dir="$(_backup_dir)" || true
  local manifest
  manifest="$(_manifest_file)" || true

  if [[ "${ARCHFORGE_TEST:-false}" == "true" ]]; then
    echo "${path}" >> "${MOCK_BACKUP_LOG:-/tmp/archforge-mock-backup-$$.log}"
  fi

  if [[ ! -e "${path}" && ! -L "${path}" ]]; then
    # Path does not exist yet — the caller is about to create it. Record
    # this *before* the caller writes the file (not after), so a crash
    # between this call and the actual write still leaves an accurate
    # manifest. `restore` uses TYPE=created to delete the file instead of
    # copying old content back, since there is no prior content to restore.
    echo "  PATH=${path}  TYPE=created" >> "${manifest}"
    return 0
  fi

  if [[ -L "${path}" ]]; then
    # Symlink — record target, do not copy content
    local target
    target="$(readlink "${path}")"
    echo "  PATH=${path}  TYPE=symlink  TARGET=${target}" >> "${manifest}"
    return 0
  fi

  # Check for unsupported types (dirs, devices, etc.)
  if [[ ! -f "${path}" ]]; then
    log_warn "backup_file: unsupported file type for ${path} — skipping"
    return 0
  fi

  # Regular file — verify readability before attempting copy
  if [[ ! -r "${path}" ]]; then
    log_warn "backup_file: ${path} is not readable by current user — skipping backup"
    return 0
  fi

  local mode owner relative_path dest_dir
  mode="$(stat -c '%a' "${path}")"
  owner="$(stat -c '%U:%G' "${path}")"
  relative_path="${path#/}"
  dest_dir="${session_dir}/${relative_path%/*}"

  mkdir -p "${dest_dir}"
  cp -p "${path}" "${session_dir}/${relative_path}"
  echo "  PATH=${path}  TYPE=file  MODE=${mode}  OWNER=${owner}  WAS_CREATED=false" >> "${manifest}"
}

record_attr() {
  # Record immutable flag state before chattr +i
  local path="$1"
  _ensure_manifest
  local attr manifest_path
  attr="$(lsattr "${path}" 2>/dev/null | awk '{print $1}' || true)"
  [[ -z "${attr}" ]] && attr='----------------'
  manifest_path="$(_manifest_file)" || true
  echo "  ATTR_PATH=${path}  LSATTR=${attr}" >> "${manifest_path}"
}

list_sessions() {
  local base="${BACKUP_BASE_DIR:-${HOME}/.local/share/archforge/backups}"
  [[ -d "${base}" ]] || { echo "No backup sessions found."; return 0; }
  local i=1
  for session_dir in "${base}"/*/; do
    [[ -d "${session_dir}" ]] || continue
    local manifest="${session_dir}session.manifest"
    local sid
    sid="$(basename "${session_dir}")"
    local modules
    local files_count
    modules="$(grep '^MODULES_MODIFIED=' "${manifest}" 2>/dev/null | cut -d= -f2 || true)"
    files_count="$(grep -c '^\s*PATH=' "${manifest}" 2>/dev/null || echo 0)"
    printf "  [%d] %s  →  modules: %s    files: %s\n" "${i}" "${sid}" "${modules:-(none)}" "${files_count}"
    i=$(( i + 1 ))
  done
}

restore_session() {
  local base="${BACKUP_BASE_DIR:-${HOME}/.local/share/archforge/backups}"
  list_sessions

  local sessions_file
  sessions_file="$(mktemp /tmp/archforge-sessions-XXXXXX)"
  find "${base}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort > "${sessions_file}" || true

  if [[ ! -s "${sessions_file}" ]]; then
    rm -f "${sessions_file}"
    log_warn "No sessions found."
    return 0
  fi

  local choice
  read -r -p "Select session number (or 'q' to quit): " choice
  [[ "${choice}" == "q" ]] && { rm -f "${sessions_file}"; return 0; }

  # Validate numeric input
  if ! [[ "${choice}" =~ ^[0-9]+$ ]]; then
    log_warn "Invalid choice: ${choice}"
    rm -f "${sessions_file}"
    return 1
  fi

  local session_dir
  session_dir="$(sed -n "${choice}p" "${sessions_file}")"
  rm -f "${sessions_file}"

  [[ -z "${session_dir}" ]] && { log_error "Session number out of range."; return 1; }

  local manifest="${session_dir}/session.manifest"
  [[ -f "${manifest}" ]] || { log_error "Manifest not found for session."; return 1; }

  echo ""
  echo "Restore options:"
  echo "  [a] Restore full session"
  echo "  [b] Restore individual file"
  local mode
  read -r -p "Choice [a/b]: " mode

  case "${mode}" in
    a) _restore_full "${session_dir}" "${manifest}" ;;
    b) _restore_file_picker "${session_dir}" "${manifest}" ;;
    *) log_warn "Invalid choice." ;;
  esac
}

_restore_full() {
  local session_dir="$1" manifest="$2"
  local line
  # shellcheck disable=SC2094
  while IFS= read -r line; do
    [[ "${line}" =~ ^[[:space:]]*PATH=([^[:space:]]+)[[:space:]]+TYPE=([^[:space:]]+) ]] || continue
    local fpath="${BASH_REMATCH[1]}"
    local ftype="${BASH_REMATCH[2]}"
    _restore_entry "${session_dir}" "${manifest}" "${fpath}" "${ftype}" "${line}"
  done < "${manifest}"
}

_restore_file_picker() {
  local session_dir="$1" manifest="$2"

  local files_file
  files_file="$(mktemp /tmp/archforge-files-XXXXXX)"
  grep -E '^\s+PATH=' "${manifest}" | sed 's/.*PATH=\([^ ]*\).*/\1/' > "${files_file}" || true

  local i=1
  while IFS= read -r f; do
    printf "  [%d] %s\n" "${i}" "${f}"
    i=$(( i + 1 ))
  done < "${files_file}"

  local choice
  read -r -p "File number: " choice

  if ! [[ "${choice}" =~ ^[0-9]+$ ]]; then
    log_warn "Invalid choice: ${choice}"
    rm -f "${files_file}"
    return 1
  fi

  local path
  path="$(sed -n "${choice}p" "${files_file}")"
  rm -f "${files_file}"

  [[ -z "${path}" ]] && { log_error "File number out of range."; return 1; }

  local line
  line="$(grep -F "PATH=${path} " "${manifest}" | head -1 || true)"
  local type=""
  [[ "${line}" =~ TYPE=([^[:space:]]+) ]] && type="${BASH_REMATCH[1]}"
  _restore_entry "${session_dir}" "${manifest}" "${path}" "${type}" "${line}"
}

_restore_entry() {
  local session_dir="$1" manifest="$2" path="$3" type="$4" manifest_line="$5"

  if [[ "${type}" == "created" ]]; then
    confirm "Delete ${path} (created by archforge — did not exist before this session)?" || return 0
  else
    confirm "Restore ${path}?" || return 0
  fi

  # Remove immutable flag if previously set
  local attr_line
  attr_line="$(grep "ATTR_PATH=${path} " "${manifest}" 2>/dev/null || true)"
  if [[ -n "${attr_line}" && "${attr_line}" =~ LSATTR=([^[:space:]]+) ]] && [[ "${BASH_REMATCH[1]}" == *i* ]]; then
    run_cmd chattr -i "${path}" 2>/dev/null || true
  fi

  case "${type}" in
    symlink)
      local target=""
      [[ "${manifest_line}" =~ TARGET=([^[:space:]]+) ]] && target="${BASH_REMATCH[1]}"
      mkdir -p "$(dirname "${path}")"
      run_cmd ln -sf "${target}" "${path}"
      log_ok "Restored symlink: ${path} → ${target}"
      ;;
    file)
      local relative="${path#/}"
      local backup_copy="${session_dir}/${relative}"
      local mode owner
      [[ "${manifest_line}" =~ MODE=([^[:space:]]+) ]] && mode="${BASH_REMATCH[1]}"
      [[ "${manifest_line}" =~ OWNER=([^[:space:]]+) ]] && owner="${BASH_REMATCH[1]}"
      mkdir -p "$(dirname "${path}")"
      run_cmd cp "${backup_copy}" "${path}"
      [[ -n "${mode}" ]]  && run_cmd chmod "${mode}" "${path}"
      [[ -n "${owner}" ]] && run_cmd chown "${owner}" "${path}"
      log_ok "Restored file: ${path}"
      ;;
    created)
      if [[ -e "${path}" || -L "${path}" ]]; then
        run_cmd rm -f "${path}"
        log_ok "Removed file created by archforge: ${path}"
      else
        log_skip "${path} already absent — nothing to remove."
      fi
      ;;
    *)
      log_warn "Unknown type '${type}' for ${path}"
      ;;
  esac
}
