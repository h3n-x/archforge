#!/usr/bin/env bats
load 'setup'

# Layer 1 static safety tests (see ARCHFORGE AUDIT VALIDATION REPORT, Phase 0/1).
# These do NOT source or execute any module -- they grep the source tree
# directly, so they are fast, dependency-free, and safe to run anywhere
# (no root, no Arch Linux, no hardware required).
#
# They codify the manual audit methodology used to find:
#   - C-1: a raw `sudo tee` writing to a real kernel path outside run_cmd(),
#     which bypassed --dry-run entirely.
#   - H-3: two modules (aur-helper.sh, firewall.sh) missing `set -euo
#     pipefail`, the standalone-execution guard, and their lib/*.sh sources,
#     relying by accident on run_modules() having pre-sourced everything.

_all_module_files() {
  find "${ARCHFORGE_DIR}/modules" -name '*.sh' | sort
}

@test "static: no module writes to a real path via 'sudo tee' / '| sudo tee' outside run_cmd" {
  # Excludes: comment-only lines, and log_*() calls whose quoted string merely
  # *mentions* a command as advice to the user (e.g. "Run 'sudo mkinitcpio -P'
  # manually...") rather than executing it.
  local f matches bad=0
  for f in $(_all_module_files) "${ARCHFORGE_DIR}/archforge"; do
    matches="$(grep -nE '(^|[^A-Za-z0-9_])(sudo[[:space:]]+tee|\|[[:space:]]*sudo[[:space:]]+tee)' "${f}" \
      | grep -vE 'run_cmd' \
      | grep -vE '^[0-9]+:[[:space:]]*#' \
      | grep -vE 'log_(info|warn|error|ok|skip|dry)[[:space:]]*"')"
    if [[ -n "${matches}" ]]; then
      echo "BYPASS FOUND in ${f}:" >&2
      echo "${matches}" >&2
      bad=1
    fi
  done
  [ "${bad}" -eq 0 ]
}

@test "static: no direct 'sudo <mutating-command>' outside run_cmd" {
  # Commands that mutate real system state and must always go through
  # run_cmd() so DRY_RUN/ARCHFORGE_TEST gate them.
  #
  # Two call sites are intentionally excluded below because they are already
  # gated by an explicit `if DRY_RUN/ARCHFORGE_TEST ... else <real command>`
  # branch rather than by run_cmd itself, and are proven safe in the audit:
  #   - performance.sh _apply_sysctl(): real branch only reached when
  #     DRY_RUN=false and ARCHFORGE_TEST=false (checked two lines above).
  #   - sensors.sh module_run(): real branch only reached under the same
  #     guard.
  local pattern='sudo[[:space:]]+(systemctl|pacman[[:space:]]+-[SR]|mkinitcpio|modprobe|chattr|usermod|gpasswd|hwclock|timedatectl|localectl|nmcli|envycontrol|pacman-key|pkgfile|vmware-networks|iw[[:space:]]+reg)'
  local f bad=0
  for f in $(_all_module_files) "${ARCHFORGE_DIR}/archforge"; do
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      case "${f}" in
        */performance.sh)
          [[ "${line}" == *"sudo sysctl --system"* ]] && continue
          ;;
        */sensors.sh)
          [[ "${line}" == *"sudo sensors-detect --auto"* ]] && continue
          ;;
      esac
      echo "BYPASS FOUND in ${f}: ${line}" >&2
      bad=1
    done < <(grep -nE "${pattern}" "${f}" \
      | grep -vE 'run_cmd' \
      | grep -vE '^[0-9]+:[[:space:]]*#' \
      | grep -vE 'log_(info|warn|error|ok|skip|dry)[[:space:]]*"')
  done
  [ "${bad}" -eq 0 ]
}

@test "static: every module sources lib/core.sh" {
  local f bad=0
  for f in $(_all_module_files); do
    if ! grep -q 'lib/core\.sh' "${f}"; then
      echo "MISSING lib/core.sh source: ${f}" >&2
      bad=1
    fi
  done
  [ "${bad}" -eq 0 ]
}

@test "static: every module using pacman_install/aur_install sources lib/packages.sh" {
  local f bad=0
  for f in $(_all_module_files); do
    if grep -qE '\b(pacman_install|aur_install)\b' "${f}" && ! grep -q 'lib/packages\.sh' "${f}"; then
      echo "USES pacman_install/aur_install but MISSING lib/packages.sh source: ${f}" >&2
      bad=1
    fi
  done
  [ "${bad}" -eq 0 ]
}

@test "static: every module using backup_file/record_attr sources lib/backup.sh" {
  local f bad=0
  for f in $(_all_module_files); do
    if grep -qE '\b(backup_file|record_attr)\b' "${f}" && ! grep -q 'lib/backup\.sh' "${f}"; then
      echo "USES backup_file/record_attr but MISSING lib/backup.sh source: ${f}" >&2
      bad=1
    fi
  done
  [ "${bad}" -eq 0 ]
}

@test "static: every module has 'set -euo pipefail'" {
  local f bad=0
  for f in $(_all_module_files); do
    if ! grep -q '^set -euo pipefail' "${f}"; then
      echo "MISSING set -euo pipefail: ${f}" >&2
      bad=1
    fi
  done
  [ "${bad}" -eq 0 ]
}

@test "static: every module has the standalone-execution BASH_SOURCE guard" {
  local f bad=0
  for f in $(_all_module_files); do
    if ! grep -q 'BASH_SOURCE\[0\]' "${f}"; then
      echo "MISSING BASH_SOURCE guard: ${f}" >&2
      bad=1
    fi
  done
  [ "${bad}" -eq 0 ]
}
