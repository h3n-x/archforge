#!/usr/bin/env bash
# lib/backup.sh — backup_file(), list_sessions(), restore_session()
# All state written to disk — safe across subshell boundaries.
# shellcheck shell=bash

_get_default_backup_base() {
  if [[ -n "${BACKUP_BASE_DIR:-}" ]]; then
    echo "${BACKUP_BASE_DIR}"
    return 0
  fi
  local user_home="${HOME}"
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    local entry
    entry="$(getent passwd "${SUDO_USER}" 2>/dev/null || true)"
    if [[ -n "${entry}" ]]; then
      user_home="$(echo "${entry}" | cut -d: -f6)"
    fi
  fi
  echo "${user_home}/.local/share/archforge/backups"
}

_backup_dir() {
  # SESSION_ID is set by the caller (main entry point or test setup)
  # shellcheck disable=SC2154
  echo "$(_get_default_backup_base)/${SESSION_ID}"
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

  if [[ "${ARCHFORGE_TEST:-false}" == "true" ]]; then
    echo "${path}" >> "${MOCK_BACKUP_LOG:-/tmp/archforge-mock-backup-$$.log}"
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_dry "backup_file ${path}"
    return 0
  fi

  _ensure_manifest

  local session_dir
  session_dir="$(_backup_dir)" || true
  local manifest
  manifest="$(_manifest_file)" || true

  local mod="${CURRENT_MODULE:-}"
  if [[ -z "${mod}" ]]; then
    local src
    for src in "${BASH_SOURCE[@]:1}"; do
      local bname
      bname="$(basename "${src}")"
      if [[ "${bname}" != "backup.sh" && "${bname}" != "core.sh" && "${bname}" != "system.sh" && "${bname}" != "hardware.sh" && "${bname}" != "packages.sh" && "${bname}" == *.sh ]]; then
        mod="${bname%.sh}"
        break
      fi
    done
  fi
  [[ -z "${mod}" ]] && mod="unknown"

  # Update MODULES_MODIFIED header in manifest if not already present
  if [[ "${mod}" != "unknown" ]]; then
    local curr_mods
    curr_mods="$(grep '^MODULES_MODIFIED=' "${manifest}" 2>/dev/null | cut -d= -f2- || true)"
    if ! [[ " ${curr_mods} " =~ [[:space:]]${mod}[[:space:]] ]]; then
      local updated_mods
      if [[ -z "${curr_mods}" ]]; then
        updated_mods="${mod}"
      else
        updated_mods="${curr_mods} ${mod}"
      fi
      sed -i "s/^MODULES_MODIFIED=.*/MODULES_MODIFIED=${updated_mods}/" "${manifest}" 2>/dev/null || true
    fi
  fi

  if [[ ! -e "${path}" && ! -L "${path}" ]]; then
    # Path does not exist yet — the caller is about to create it. Record
    # this *before* the caller writes the file (not after), so a crash
    # between this call and the actual write still leaves an accurate
    # manifest. `restore` uses TYPE=created to delete the file instead of
    # copying old content back, since there is no prior content to restore.
    echo "  PATH=${path}  TYPE=created  MODULE=${mod}" >> "${manifest}"
    return 0
  fi

  if [[ -L "${path}" ]]; then
    # Symlink — record target, do not copy content
    local target
    target="$(readlink "${path}")"
    echo "  PATH=${path}  TYPE=symlink  TARGET=${target}  MODULE=${mod}" >> "${manifest}"
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
  echo "  PATH=${path}  TYPE=file  MODE=${mode}  OWNER=${owner}  WAS_CREATED=false  MODULE=${mod}" >> "${manifest}"
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
  local base
  base="$(_get_default_backup_base)"
  [[ -d "${base}" ]] || { echo "No backup sessions found."; return 0; }
  local i=1
  for session_dir in "${base}"/*/; do
    [[ -d "${session_dir}" ]] || continue
    local manifest="${session_dir}session.manifest"
    local sid
    sid="$(basename "${session_dir}")"
    local modules
    local files_count
    modules="$(grep '^MODULES_MODIFIED=' "${manifest}" 2>/dev/null | cut -d= -f2- || true)"
    files_count="$(grep -c '^\s*PATH=' "${manifest}" 2>/dev/null || echo 0)"
    printf "  [%d] %s  →  modules: %s    files: %s\n" "${i}" "${sid}" "${modules:-(none)}" "${files_count}"
    i=$(( i + 1 ))
  done
}

restore_session() {
  local target_session="${1:-${RESTORE_SESSION:-}}"
  local target_module="${2:-${RESTORE_MODULE:-}}"
  local base
  base="$(_get_default_backup_base)"

  local session_dir=""

  if [[ -n "${target_session}" ]]; then
    if [[ -d "${base}/${target_session}" ]]; then
      session_dir="${base}/${target_session}"
    elif [[ -d "${target_session}" ]]; then
      session_dir="${target_session}"
    else
      local match
      match="$(find "${base}" -mindepth 1 -maxdepth 1 -type d -name "*${target_session}*" 2>/dev/null | head -1 || true)"
      if [[ -n "${match}" && -d "${match}" ]]; then
        session_dir="${match}"
      else
        log_error "Session not found: ${target_session}"
        return 1
      fi
    fi
  else
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

    session_dir="$(sed -n "${choice}p" "${sessions_file}")"
    rm -f "${sessions_file}"
  fi

  [[ -z "${session_dir}" ]] && { log_error "Session number out of range."; return 1; }

  local manifest="${session_dir}/session.manifest"
  [[ -f "${manifest}" ]] || { log_error "Manifest not found for session: ${session_dir}"; return 1; }

  if [[ -n "${target_module}" ]]; then
    _restore_module "${session_dir}" "${manifest}" "${target_module}"
    return $?
  fi

  echo ""
  echo "Restore options:"
  echo "  [a] Restore full session"
  echo "  [b] Restore individual file"
  echo "  [c] Restore by module"
  local mode
  read -r -p "Choice [a/b/c]: " mode

  case "${mode}" in
    a) _restore_full "${session_dir}" "${manifest}" ;;
    b) _restore_file_picker "${session_dir}" "${manifest}" ;;
    c) _restore_module_picker "${session_dir}" "${manifest}" ;;
    *) log_warn "Invalid choice." ;;
  esac
}

_restore_module() {
  local session_dir="$1" manifest="$2" target_mod="$3"
  local count=0
  local line

  # shellcheck disable=SC2094
  while IFS= read -r line; do
    [[ "${line}" =~ ^[[:space:]]*PATH=([^[:space:]]+)[[:space:]]+TYPE=([^[:space:]]+) ]] || continue
    local fpath="${BASH_REMATCH[1]}"
    local ftype="${BASH_REMATCH[2]}"
    local mod=""
    [[ "${line}" =~ MODULE=([^[:space:]]+) ]] && mod="${BASH_REMATCH[1]}"
    if [[ "${mod}" == "${target_mod}" ]]; then
      count=$(( count + 1 ))
      _restore_entry "${session_dir}" "${manifest}" "${fpath}" "${ftype}" "${line}"
    fi
  done < "${manifest}"

  if [[ ${count} -eq 0 ]]; then
    log_warn "No files recorded for module '${target_mod}' in session manifest."
    return 1
  fi
  log_ok "Module '${target_mod}' restore completed (${count} file(s) processed)."
}

_restore_module_picker() {
  local session_dir="$1" manifest="$2"

  local mods_file
  mods_file="$(mktemp /tmp/archforge-mods-XXXXXX)"
  grep -o 'MODULE=[^[:space:]]*' "${manifest}" 2>/dev/null | cut -d= -f2 | sort -u > "${mods_file}" || true

  if [[ ! -s "${mods_file}" ]]; then
    local header_mods
    header_mods="$(grep '^MODULES_MODIFIED=' "${manifest}" 2>/dev/null | cut -d= -f2- || true)"
    local hm
    for hm in ${header_mods}; do
      echo "${hm}" >> "${mods_file}"
    done
  fi

  if [[ ! -s "${mods_file}" ]]; then
    rm -f "${mods_file}"
    log_warn "No module information recorded in session manifest."
    return 1
  fi

  echo "Modules in this session:"
  local i=1
  while IFS= read -r m; do
    printf "  [%d] %s\n" "${i}" "${m}"
    i=$(( i + 1 ))
  done < "${mods_file}"

  local choice
  read -r -p "Select module number: " choice

  if ! [[ "${choice}" =~ ^[0-9]+$ ]]; then
    log_warn "Invalid choice: ${choice}"
    rm -f "${mods_file}"
    return 1
  fi

  local selected_mod
  selected_mod="$(sed -n "${choice}p" "${mods_file}")"
  rm -f "${mods_file}"

  [[ -z "${selected_mod}" ]] && { log_error "Module number out of range."; return 1; }

  _restore_module "${session_dir}" "${manifest}" "${selected_mod}"
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

_needs_root_for_path() {
  local target="$1"
  [[ "${EUID}" -eq 0 ]] && return 1
  local parent
  parent="$(dirname "${target}")"
  if [[ -e "${target}" ]]; then
    [[ ! -w "${target}" ]]
  else
    [[ ! -w "${parent}" ]]
  fi
}

_restore_entry() {
  local session_dir="$1" manifest="$2" path="$3" type="$4" manifest_line="$5"

  if [[ "${type}" == "created" ]]; then
    confirm "Delete ${path} (created by archforge — did not exist before this session)?" || return 0
  else
    confirm "Restore ${path}?" || return 0
  fi

  local sudo_cmd=""
  if _needs_root_for_path "${path}"; then
    sudo_cmd="sudo"
  fi

  # Remove immutable flag if previously set
  local attr_line
  attr_line="$(grep "ATTR_PATH=${path} " "${manifest}" 2>/dev/null || true)"
  if [[ -n "${attr_line}" && "${attr_line}" =~ LSATTR=([^[:space:]]+) ]] && [[ "${BASH_REMATCH[1]}" == *i* ]]; then
    if [[ -n "${sudo_cmd}" ]]; then
      run_cmd sudo chattr -i "${path}" 2>/dev/null || true
    else
      run_cmd chattr -i "${path}" 2>/dev/null || true
    fi
  fi

  case "${type}" in
    symlink)
      local target=""
      [[ "${manifest_line}" =~ TARGET=([^[:space:]]+) ]] && target="${BASH_REMATCH[1]}"
      if [[ -n "${sudo_cmd}" ]]; then
        run_cmd sudo mkdir -p "$(dirname "${path}")"
        run_cmd sudo ln -sf "${target}" "${path}"
      else
        mkdir -p "$(dirname "${path}")"
        run_cmd ln -sf "${target}" "${path}"
      fi
      log_ok "Restored symlink: ${path} → ${target}"
      ;;
    file)
      local relative="${path#/}"
      local backup_copy="${session_dir}/${relative}"
      local mode owner
      [[ "${manifest_line}" =~ MODE=([^[:space:]]+) ]] && mode="${BASH_REMATCH[1]}"
      [[ "${manifest_line}" =~ OWNER=([^[:space:]]+) ]] && owner="${BASH_REMATCH[1]}"
      if [[ -n "${sudo_cmd}" ]]; then
        run_cmd sudo mkdir -p "$(dirname "${path}")"
        run_cmd sudo cp "${backup_copy}" "${path}"
        [[ -n "${mode}" ]]  && run_cmd sudo chmod "${mode}" "${path}"
        [[ -n "${owner}" ]] && run_cmd sudo chown "${owner}" "${path}"
      else
        mkdir -p "$(dirname "${path}")"
        run_cmd cp "${backup_copy}" "${path}"
        [[ -n "${mode}" ]]  && run_cmd chmod "${mode}" "${path}"
        [[ -n "${owner}" ]] && run_cmd chown "${owner}" "${path}"
      fi
      log_ok "Restored file: ${path}"
      ;;
    created)
      if [[ -e "${path}" || -L "${path}" ]]; then
        if [[ -n "${sudo_cmd}" ]]; then
          run_cmd sudo rm -f "${path}"
        else
          run_cmd rm -f "${path}"
        fi
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
