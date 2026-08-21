#!/usr/bin/env bash
# lib/menu.sh — interactive module selection menu (native bash, no fzf)
# shellcheck shell=bash

# ── Logical execution order ────────────────────────────────────────────────────
MODULE_EXECUTION_ORDER=(
  "pacman" "aur-helper"
  "systemd" "users-groups"
  "dns" "firewall" "antivirus"
  "network"
  "tlp" "acpid"
  "ssd" "performance" "sensors"
  "libinput" "keyboard"
  "fonts" "locale"
  "nouveau" "nvidia"
  "steam"
  "printing"
  "vmware-host"
)

# Widest column count of the "ARCH FORGE" ASCII block (must match longest line).
# Subtitle centering and the "Select modules" box use this width.
readonly ARCHFORGE_BANNER_WIDTH=78

# ── UTF-8 detection ────────────────────────────────────────────────────────────
_has_utf8() {
  local lc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  [[ "${lc,,}" == *utf-8* ]] || [[ "${lc,,}" == *utf8* ]]
}

# ── Banner ────────────────────────────────────────────────────────────────────
_BANNER_PRINTED=false

_print_banner() {
  [[ "${_BANNER_PRINTED}" == true ]] && return 0
  _BANNER_PRINTED=true
  local c=$'\033[0;36m'
  local b=$'\033[1m'
  local d=$'\033[2m'
  local r=$'\033[0m'

  printf '%s\n' "${c}" \
    ' █████╗ ██████╗  ██████╗██╗  ██╗    ███████╗ ██████╗ ██████╗  ██████╗ ███████╗' \
    '██╔══██╗██╔══██╗██╔════╝██║  ██║    ██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝' \
    '███████║██████╔╝██║     ███████║    █████╗  ██║   ██║██████╔╝██║  ███╗█████╗  ' \
    '██╔══██║██╔══██╗██║     ██╔══██║    ██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝  ' \
    '██║  ██║██║  ██║╚██████╗██║  ██║    ██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗' \
    '╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝    ╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝' \
    "${r}" >&2

  # Subtitle lines centered on widest ASCII row; keep *_vis in sync with visible text.
  local _banner_w="${ARCHFORGE_BANNER_WIDTH}"
  local _line1_vis='archforge — post-installation toolkit for Arch Linux'
  local _ver="${ARCHFORGE_VERSION:-0.2.0}"
  local _line2_vis="v${_ver} · https://github.com/h3n-x/archforge"
  local _pad1=$(( (_banner_w - ${#_line1_vis}) / 2 ))
  local _pad2=$(( (_banner_w - ${#_line2_vis}) / 2 ))
  (( _pad1 < 0 )) && _pad1=0
  (( _pad2 < 0 )) && _pad2=0

  printf '%*s' "${_pad1}" '' >&2
  # shellcheck disable=SC2059
  printf "${b}archforge${r} ${d}—${r} post-installation toolkit for Arch Linux\n" >&2
  printf '%*s' "${_pad2}" '' >&2
  # shellcheck disable=SC2059
  printf "${d}v%s · ${c}https://github.com/h3n-x/archforge${r}\n" "${_ver}" >&2
  printf '\n' >&2
}

# ── Execution-order sort ───────────────────────────────────────────────────────
_sort_by_execution_order() {
  local -a selected=("$@")
  local -a ordered=()
  local module sel found

  for module in "${MODULE_EXECUTION_ORDER[@]}"; do
    for sel in "${selected[@]}"; do
      [[ "${sel}" == "${module}" ]] && ordered+=("${module}") && break
    done
  done

  for sel in "${selected[@]}"; do
    found=false
    for module in "${MODULE_EXECUTION_ORDER[@]}"; do
      [[ "${sel}" == "${module}" ]] && found=true && break
    done
    [[ "${found}" == false ]] && ordered+=("${sel}")
  done

  printf '%s\n' "${ordered[@]}"
}

# ── Entry parser ──────────────────────────────────────────────────────────────
# Entry format: "id:Category: Name:desc:hw_warn"
# MODULE_NAME = "Category: Name" contains a colon — peel fields from both ends.
_parse_entry() {
  local entry="$1"
  local -n _pe_id=$2
  local -n _pe_cat=$3
  local -n _pe_short=$4
  local -n _pe_desc=$5
  local -n _pe_hw=$6

  _pe_id="${entry%%:*}"
  local rest="${entry#*:}"

  _pe_hw="${rest##*:}"
  rest="${rest%:*}"

  _pe_desc="${rest##*:}"
  local name="${rest%:*}"

  if [[ "${name}" == *':'* ]]; then
    _pe_cat="${name%%:*}"
    local after="${name#*:}"
    _pe_short="${after# }"
  else
    _pe_cat="Other"
    _pe_short="${name:-${_pe_id}}"
  fi
}

# ── Compact menu item: [nn] id only (+ optional ⚠), UTF-8 colors ──────────────
_menu_compact_item_utf8() {
  local num="$1" mid="$2" mhw="$3" idw="$4"
  local b=$'\033[1m' y=$'\033[1;33m' dc=$'\033[2;36m' r=$'\033[0m'
  local num_col="${dc}"
  if [[ -n "${mhw}" ]]; then
    num_col="${y}"
  fi
  printf '%s[%2d]%s  %s%-*s%s' "${num_col}" "${num}" "${r}" "${b}" "${idw}" "${mid}" "${r}"
  # Fixed 2 display cols after id so left/right columns stay aligned (matches " ⚠").
  if [[ -n "${mhw}" ]]; then
    printf ' %s⚠%s' "${y}" "${r}"
  else
    printf '  '
  fi
  return 0
}

_menu_compact_item_ascii() {
  local num="$1" mid="$2" mhw="$3" idw="$4"
  printf ' [%2d]  %-*s' "${num}" "${idw}" "${mid}"
  if [[ -n "${mhw}" ]]; then
    printf ' !'
  else
    printf '  '
  fi
  return 0
}

# ── Module list (flat): two columns, no categories / borders / descriptions ──
# Order matches __list (same as ALL_MODULES in archforge). Numbers 1…n_left left col, rest right.
# shellcheck disable=SC2034
_build_and_print_module_table() {
  # shellcheck disable=SC2178
  local -n __list=$1
  # shellcheck disable=SC2178
  local -n __by_number=$2
  # shellcheck disable=SC2178
  local -n __all_ids=$3

  local -a _nums=() _mids=() _mhws=()
  local counter=1
  local entry _eid _ecat _eshort _edesc _ehw

  for entry in "${__list[@]}"; do
    _parse_entry "${entry}" _eid _ecat _eshort _edesc _ehw
    __by_number["${counter}"]="${_eid}"
    __all_ids+=("${_eid}")
    _nums+=("${counter}")
    _mids+=("${_eid}")
    _mhws+=("${_ehw}")
    counter=$(( counter + 1 ))
  done

  local n=${#_mids[@]}
  (( n == 0 )) && return 0

  local idw=10
  local mid ml
  for mid in "${_mids[@]}"; do
    ml=${#mid}
    if (( ml > idw )); then
      idw=${ml}
    fi
  done
  if (( idw > 20 )); then
    idw=20
  fi

  local n_left=$(( (n + 1) / 2 ))
  local _use_utf8=false
  if _has_utf8; then
    _use_utf8=true
  fi

  local row=0 li ri
  # Use while, not for ((…)), so set -e (archforge) does not exit when the final C-for test fails.
  while (( row < n_left )); do
    li=${row}
    ri=$(( row + n_left ))
    printf '  ' >&2
    if [[ "${_use_utf8}" == true ]]; then
      _menu_compact_item_utf8 "${_nums[li]}" "${_mids[li]}" "${_mhws[li]}" "${idw}" >&2
      printf '    ' >&2
      if (( ri < n )); then
        _menu_compact_item_utf8 "${_nums[ri]}" "${_mids[ri]}" "${_mhws[ri]}" "${idw}" >&2
      fi
      printf '\n' >&2
    else
      _menu_compact_item_ascii "${_nums[li]}" "${_mids[li]}" "${_mhws[li]}" "${idw}" >&2
      printf '    ' >&2
      if (( ri < n )); then
        _menu_compact_item_ascii "${_nums[ri]}" "${_mids[ri]}" "${_mhws[ri]}" "${idw}" >&2
      fi
      printf '\n' >&2
    fi
    row=$(( row + 1 ))
  done

  printf '\n' >&2
}

# ── Input prompt ───────────────────────────────────────────────────────────────
# Box width matches ASCII banner (not terminal width) so borders do not extend past the logo.
_print_prompt() {
  local c=$'\033[0;36m'
  local d=$'\033[2m'
  local r=$'\033[0m'

  local box_w="${ARCHFORGE_BANNER_WIDTH}"

  if _has_utf8; then
    # Header fill: "╭─  Select modules " + fill + "╮"
    # "╭─  Select modules " = 19 chars; then fill + "╮" must reach box_w
    # fill_len = box_w - 19 - 1 (╮)  = box_w - 20
    local hdr_fill
    # shellcheck disable=SC2312
    printf -v hdr_fill '%0.s─' $(seq 1 $(( box_w - 20 )))
    local bot_fill
    # shellcheck disable=SC2312
    printf -v bot_fill '%0.s─' $(seq 1 $(( box_w - 2 )))

    # Content rows: "│" + 2 spaces + text + pad + "│" = box_w (avoid UTF-8 in pad width).
    local content_w=$(( box_w - 4 ))  # between "│  " and "  │"
    printf '%s╭─  Select modules %s╮%s\n' "${d}" "${hdr_fill}" "${r}" >&2
    local row1="Numbers, names, or all - q quits - separate with spaces or commas"
    local row1_pad=$(( content_w - ${#row1} ))
    (( row1_pad < 0 )) && row1_pad=0
    printf '%s│%s  %s%*s%s%s│%s\n' \
      "${d}" "${r}" "${row1}" "${row1_pad}" "" "${r}" "${d}" "${r}" >&2
    printf '%s╰%s╯%s\n' "${d}" "${bot_fill}" "${r}" >&2
    printf ' %s❯%s ' "${c}" "${r}" >&2
  else
    local afill_len=$(( box_w - 20 ))
    (( afill_len < 1 )) && afill_len=1
    local afill
    # shellcheck disable=SC2312
    printf -v afill '%0.s-' $(seq 1 "${afill_len}")
    printf '+-- Select modules %s+\n' "${afill}" >&2
    local row1="Numbers, names, or all - q quits - separate with spaces or commas"
    local content_w=$(( box_w - 4 ))
    local row1_pad=$(( content_w - ${#row1} ))
    (( row1_pad < 0 )) && row1_pad=0
    printf '|  %s%*s|\n' "${row1}" "${row1_pad}" "" >&2
    local bfill
    # shellcheck disable=SC2312
    printf -v bfill '%0.s-' $(seq 1 $(( box_w - 2 )))
    printf '+%s+\n' "${bfill}" >&2
    printf ' > ' >&2
  fi
}

# ── Public entry point ─────────────────────────────────────────────────────────
show_menu() {
  # shellcheck disable=SC2178
  local -n _module_list=$1
  SELECTED_MODULES=()

  _print_banner

  if [[ ${#_module_list[@]} -eq 0 ]]; then
    log_warn "No modules available to select."
    return 0
  fi

  declare -A _MODULE_BY_NUMBER=()
  local -a _ALL_MODULE_IDS=()
  # Copy via _module_list: nameref to main's menu_entries works here, but
  # `local -n __list=menu_entries` inside _build often sees only one element (dynamic scope).
  local -a _menu_for_table=()
  _menu_for_table=("${_module_list[@]}")
  _build_and_print_module_table _menu_for_table _MODULE_BY_NUMBER _ALL_MODULE_IDS

  declare -A _MODULE_BY_NAME=()
  local _mid
  for _mid in "${_ALL_MODULE_IDS[@]}"; do
    _MODULE_BY_NAME["${_mid}"]="${_mid}"
  done

  local total="${#_ALL_MODULE_IDS[@]}"

  _print_prompt
  local input
  read -r input

  [[ -z "${input}" || "${input}" == "q" ]] && return 0

  if [[ "${input}" == "all" ]]; then
    SELECTED_MODULES=("${_ALL_MODULE_IDS[@]}")
    return 0
  fi

  input="${input//,/ }"
  local -a _raw_selected=()
  local -a _tokens=()
  read -ra _tokens <<< "${input}"

  local tok resolved
  for tok in "${_tokens[@]}"; do
    if [[ "${tok}" =~ ^[0-9]+$ ]]; then
      if (( tok >= 1 && tok <= total )); then
        resolved="${_MODULE_BY_NUMBER[${tok}]}"
        [[ -n "${resolved}" ]] && _raw_selected+=("${resolved}")
      else
        log_warn "Number out of range: ${tok} (valid: 1–${total})"
      fi
    elif [[ -n "${_MODULE_BY_NAME[${tok}]+_}" ]]; then
      _raw_selected+=("${tok}")
    else
      log_warn "Unknown module: '${tok}' — skipped"
    fi
  done

  if [[ ${#_raw_selected[@]} -gt 0 ]]; then
    local -a _reordered=()
    # shellcheck disable=SC2312
    mapfile -t _reordered < <(_sort_by_execution_order "${_raw_selected[@]}")
    SELECTED_MODULES=("${_reordered[@]}")
  fi
}
