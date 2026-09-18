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

# ── Color & Styling Initialization ────────────────────────────────────────────
_init_colors() {
  if [[ -n "${NO_COLOR:-}" || "${TERM:-}" == "dumb" ]]; then
    C_CYAN=""
    C_BOLD=""
    C_DIM=""
    C_YELLOW=""
    C_RED=""
    C_GREEN=""
    C_RESET=""
    C_DIM_CYAN=""
  else
    C_CYAN=$'\033[0;36m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_YELLOW=$'\033[1;33m'
    C_RED=$'\033[1;31m'
    C_GREEN=$'\033[1;32m'
    C_RESET=$'\033[0m'
    C_DIM_CYAN=$'\033[2;36m'
  fi
}

# ── Banner ────────────────────────────────────────────────────────────────────
_BANNER_PRINTED=false

_print_banner() {
  [[ "${_BANNER_PRINTED}" == true ]] && return 0
  _BANNER_PRINTED=true
  _init_colors
  local c="${C_CYAN}"
  local b="${C_BOLD}"
  local d="${C_DIM}"
  local r="${C_RESET}"

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
  local _line2_vis='v0.1.0 · https://github.com/h3n-x/archforge'
  local _pad1=$(( (_banner_w - ${#_line1_vis}) / 2 ))
  local _pad2=$(( (_banner_w - ${#_line2_vis}) / 2 ))
  (( _pad1 < 0 )) && _pad1=0
  (( _pad2 < 0 )) && _pad2=0

  printf '%*s' "${_pad1}" '' >&2
  # shellcheck disable=SC2059
  printf "${b}archforge${r} ${d}—${r} post-installation toolkit for Arch Linux\n" >&2
  printf '%*s' "${_pad2}" '' >&2
  # shellcheck disable=SC2059
  printf "${d}v0.1.0 · ${c}https://github.com/h3n-x/archforge${r}\n" >&2
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
  _init_colors
  local b="${C_BOLD}" y="${C_YELLOW}" dc="${C_DIM_CYAN}" r="${C_RESET}"
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

# ── Module list table: dynamic columns based on terminal width ────────────────
# Order matches __list (same as ALL_MODULES in archforge).
# cols >= 90: 2-column balanced grid
# cols < 90:  1-column detailed list with descriptions
# shellcheck disable=SC2034
_build_and_print_module_table() {
  # shellcheck disable=SC2178
  local -n __list=$1
  # shellcheck disable=SC2178
  local -n __by_number=$2
  # shellcheck disable=SC2178
  local -n __all_ids=$3

  local -a _nums=() _mids=() _mhws=() _mdescs=()
  local counter=1
  local entry _eid _ecat _eshort _edesc _ehw

  for entry in "${__list[@]}"; do
    _parse_entry "${entry}" _eid _ecat _eshort _edesc _ehw
    __by_number["${counter}"]="${_eid}"
    __all_ids+=("${_eid}")
    _nums+=("${counter}")
    _mids+=("${_eid}")
    _mhws+=("${_ehw}")
    _mdescs+=("${_edesc}")
    counter=$(( counter + 1 ))
  done

  local n=${#_mids[@]}
  (( n == 0 )) && return 0

  local cols="${COLUMNS:-}"
  [[ -z "${cols}" ]] && cols="$(tput cols 2>/dev/null || echo 80)"

  local _use_utf8=false
  _has_utf8 && _use_utf8=true

  _init_colors
  local b="${C_BOLD}" y="${C_YELLOW}" dc="${C_DIM_CYAN}" d="${C_DIM}" r="${C_RESET}"

  # ── Layout Branch: 1 column if cols < 90 ────────────────────────────────────
  if (( cols < 90 )); then
    local idx
    for (( idx=0; idx<n; idx++ )); do
      local num="${_nums[idx]}"
      local mid="${_mids[idx]}"
      local mhw="${_mhws[idx]}"
      local desc="${_mdescs[idx]}"
      local num_col="${dc}"
      [[ -n "${mhw}" ]] && num_col="${y}"

      local warn_mark="  "
      if [[ -n "${mhw}" ]]; then
        [[ "${_use_utf8}" == true ]] && warn_mark="${y}⚠${r} " || warn_mark="! "
      fi

      if [[ -n "${desc}" ]]; then
        printf '  %s[%2d]%s  %s%-14s%s %s%s—%s %s\n' \
          "${num_col}" "${num}" "${r}" \
          "${b}" "${mid}" "${r}" \
          "${warn_mark}" "${d}" "${r}" "${desc}" >&2
      else
        printf '  %s[%2d]%s  %s%-14s%s %s\n' \
          "${num_col}" "${num}" "${r}" \
          "${b}" "${mid}" "${r}" \
          "${warn_mark}" >&2
      fi
    done
    printf '\n' >&2
    return 0
  fi

  # ── Layout Branch: 2 columns if cols >= 90 ──────────────────────────────────
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

  local row=0 li ri
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
_print_prompt() {
  _init_colors
  local c="${C_CYAN}"
  local d="${C_DIM}"
  local r="${C_RESET}"

  local box_w="${ARCHFORGE_BANNER_WIDTH}"

  if _has_utf8; then
    local hdr_fill
    printf -v hdr_fill '%0.s─' $(seq 1 $(( box_w - 20 )))
    local bot_fill
    printf -v bot_fill '%0.s─' $(seq 1 $(( box_w - 2 )))

    local content_w=$(( box_w - 4 ))
    printf '%s╭─  Select modules %s╮%s\n' "${d}" "${hdr_fill}" "${r}" >&2
    local row1="Numbers, ranges (1-4), names, or all - q quits - separate with spaces"
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
    printf -v afill '%0.s-' $(seq 1 "${afill_len}")
    printf '+-- Select modules %s+\n' "${afill}" >&2
    local row1="Numbers, ranges (1-4), names, or all - q quits - separate with spaces"
    local content_w=$(( box_w - 4 ))
    local row1_pad=$(( content_w - ${#row1} ))
    (( row1_pad < 0 )) && row1_pad=0
    printf '|  %s%*s|\n' "${row1}" "${row1_pad}" "" >&2
    local bfill
    printf -v bfill '%0.s-' $(seq 1 $(( box_w - 2 )))
    printf '+%s+\n' "${bfill}" >&2
    printf ' > ' >&2
  fi
}

# ── TUI Engine Detection ──────────────────────────────────────────────────────
# Detects whether to use D3 (fzf with preview) or D1 (native bash fallback).
_detect_tui_engine() {
  # (a) If stdin or stdout is not a TTY (headless, pipe, CI), no interactive TUI
  if [[ ! -t 0 || ! -t 1 ]] && [[ "${ARCHFORGE_TEST_TTY:-false}" != "true" ]]; then
    echo "none"
    return 0
  fi

  # (b) User explicitly forced classic mode via env or flag
  if [[ "${ARCHFORGE_TUI:-}" == "classic" ]]; then
    echo "d1"
    return 0
  fi

  # (c) Check if fzf is available in PATH
  if ! command -v fzf &>/dev/null; then
    echo "d1"
    return 0
  fi

  # (e) Check terminal geometry
  local cols lines
  cols="${COLUMNS:-}"
  lines="${LINES:-}"
  [[ -z "${cols}" ]] && cols="$(tput cols 2>/dev/null || echo 80)"
  [[ -z "${lines}" ]] && lines="$(tput lines 2>/dev/null || echo 24)"

  if (( cols < 80 || lines < 20 )); then
    # Terminal too small for side-by-side preview; degrade to D1
    echo "d1"
    return 0
  fi

  # (d) Check if fzf supports --preview
  if fzf --help 2>&1 | grep -q -- '--preview'; then
    echo "d3"
    return 0
  fi

  echo "d1"
}

# ── Preview Card Renderer ─────────────────────────────────────────────────────
_render_module_preview_card() {
  local target="$1" name="$2" desc="$3" hw_warn="$4" wiki="$5" pkgs="$6" aur_pkgs="$7" deps="$8"

  _init_colors
  local c_cyan="${C_CYAN}"
  local c_bold="${C_BOLD}"
  local c_dim="${C_DIM}"
  local c_yellow="${C_YELLOW}"
  local c_green="${C_GREEN}"
  local c_reset="${C_RESET}"

  local title="${name:-${target}}"

  printf '%s╭─────────────────────────────────────────────────────────────╮%s\n' "${c_cyan}" "${c_reset}"
  printf '%s│%s %s%-59s%s %s│%s\n' "${c_cyan}" "${c_reset}" "${c_bold}" "${title:0:59}" "${c_reset}" "${c_cyan}" "${c_reset}"
  printf '%s│%s %s[%s]%s%*s %s│%s\n' "${c_cyan}" "${c_reset}" "${c_dim}" "${target}" "${c_reset}" "$(( 57 - ${#target} ))" "" "${c_cyan}" "${c_reset}"
  printf '%s╰─────────────────────────────────────────────────────────────╯%s\n\n' "${c_cyan}" "${c_reset}"

  if [[ -n "${hw_warn}" ]]; then
    printf '%s⚠  ADVERTENCIA / HARDWARE:%s\n' "${c_yellow}" "${c_reset}"
    printf '   %s%s%s\n\n' "${c_bold}" "${hw_warn}" "${c_reset}"
  fi

  if [[ -n "${desc}" ]]; then
    printf '%sDESCRIPCIÓN:%s\n' "${c_bold}" "${c_reset}"
    printf '   %s\n\n' "${desc}"
  fi

  if [[ -n "${wiki}" ]]; then
    printf '%sDOCUMENTACIÓN OFICIAL (ArchWiki):%s\n' "${c_bold}" "${c_reset}"
    local url
    while IFS= read -r url; do
      [[ -n "${url}" ]] && printf '   • %s%s%s\n' "${c_cyan}" "${url}" "${c_reset}"
    done < <(wiki_source_to_urls "${wiki}")
    echo ""
  fi

  if [[ -n "${pkgs}" ]]; then
    printf '%sPAQUETES OFICIALES (Pacman):%s\n' "${c_bold}" "${c_reset}"
    printf '   %s%s%s\n\n' "${c_green}" "${pkgs}" "${c_reset}"
  fi

  if [[ -n "${aur_pkgs}" ]]; then
    printf '%sPAQUETES AUR:%s\n' "${c_bold}" "${c_reset}"
    printf '   %s%s%s\n\n' "${c_yellow}" "${aur_pkgs}" "${c_reset}"
  fi

  if [[ -n "${deps}" ]]; then
    printf '%sDEPENDENCIAS DE MÓDULO:%s\n' "${c_dim}" "${c_reset}"
    printf '   %s\n\n' "${deps}"
  fi
}

preview_module() {
  local target="$1"
  local file=""
  if declare -f _find_module_file &>/dev/null; then
    file="$(_find_module_file "${target}" 2>/dev/null || true)"
  fi
  if [[ -z "${file}" || ! -f "${file}" ]]; then
    echo "Module not found: ${target}" >&2
    return 1
  fi

  local out
  out="$(ARCHFORGE_DIR="${ARCHFORGE_DIR}" ARCHFORGE_TEST=true bash -c '
    source "$1"
    module_info
    printf "MODULE_NAME=%q\n"        "${MODULE_NAME:-}"
    printf "MODULE_DESC=%q\n"        "${MODULE_DESC:-}"
    printf "MODULE_HW_WARN=%q\n"     "${MODULE_HW_WARN:-}"
    printf "MODULE_WIKI_SOURCE=%q\n" "${MODULE_WIKI_SOURCE:-}"
    printf "MODULE_PACKAGES=%q\n"    "${MODULE_PACKAGES:-}"
    printf "MODULE_AUR_PACKAGES=%q\n" "${MODULE_AUR_PACKAGES:-}"
    printf "MODULE_DEPENDS=%q\n"     "${MODULE_DEPENDS:-}"
  ' _ "${file}" 2>/dev/null)" || return 1

  local MODULE_NAME="" MODULE_DESC="" MODULE_HW_WARN="" MODULE_WIKI_SOURCE=""
  local MODULE_PACKAGES="" MODULE_AUR_PACKAGES="" MODULE_DEPENDS=""
  local line
  while IFS= read -r line; do
    case "${line}" in
      MODULE_NAME=*)        eval "MODULE_NAME=${line#MODULE_NAME=}"               ;;
      MODULE_DESC=*)        eval "MODULE_DESC=${line#MODULE_DESC=}"               ;;
      MODULE_HW_WARN=*)     eval "MODULE_HW_WARN=${line#MODULE_HW_WARN=}"         ;;
      MODULE_WIKI_SOURCE=*) eval "MODULE_WIKI_SOURCE=${line#MODULE_WIKI_SOURCE=}" ;;
      MODULE_PACKAGES=*)    eval "MODULE_PACKAGES=${line#MODULE_PACKAGES=}"       ;;
      MODULE_AUR_PACKAGES=*) eval "MODULE_AUR_PACKAGES=${line#MODULE_AUR_PACKAGES=}" ;;
      MODULE_DEPENDS=*)     eval "MODULE_DEPENDS=${line#MODULE_DEPENDS=}"         ;;
    esac
  done <<< "${out}"

  _render_module_preview_card "${target}" "${MODULE_NAME}" "${MODULE_DESC}" "${MODULE_HW_WARN}" "${MODULE_WIKI_SOURCE}" "${MODULE_PACKAGES}" "${MODULE_AUR_PACKAGES}" "${MODULE_DEPENDS}"
}

# ── D1 Native Bash Selector ───────────────────────────────────────────────────
_show_menu_d1() {
  # shellcheck disable=SC2178
  local -n _m_list=$1
  SELECTED_MODULES=()

  _print_banner

  declare -A _MODULE_BY_NUMBER=()
  local -a _ALL_MODULE_IDS=()
  local -a _menu_for_table=()
  _menu_for_table=("${_m_list[@]}")
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

  [[ -z "${input}" || "${input}" == "q" || "${input}" == "Q" ]] && return 0

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
    if [[ "${tok}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local start="${BASH_REMATCH[1]}"
      local end="${BASH_REMATCH[2]}"
      local i
      if (( start <= end )); then
        for (( i=start; i<=end; i++ )); do
          if (( i >= 1 && i <= total )); then
            resolved="${_MODULE_BY_NUMBER[${i}]}"
            [[ -n "${resolved}" ]] && _raw_selected+=("${resolved}")
          fi
        done
      fi
    elif [[ "${tok}" =~ ^[0-9]+$ ]]; then
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
    mapfile -t _reordered < <(_sort_by_execution_order "${_raw_selected[@]}")
    SELECTED_MODULES=("${_reordered[@]}")
  fi
}

# ── D3 FZF Fuzzy Multi-Selector with Preview ──────────────────────────────────
_show_menu_d3() {
  # shellcheck disable=SC2178
  local -n _m_list=$1
  SELECTED_MODULES=()

  local -a fzf_items=()
  local entry _eid _ecat _eshort _edesc _ehw
  local warn_str item_line

  for entry in "${_m_list[@]}"; do
    _parse_entry "${entry}" _eid _ecat _eshort _edesc _ehw
    if [[ -n "${_ehw}" ]]; then
      warn_str="⚠"
    else
      warn_str=" "
    fi
    printf -v item_line '%-14s %s  %s' "${_eid}" "${warn_str}" "${_eshort}"
    fzf_items+=("${item_line}")
  done

  local preview_bin="${ARCHFORGE_DIR}/archforge"
  [[ ! -x "${preview_bin}" ]] && preview_bin="archforge"

  local color_flag="--ansi"
  if [[ -n "${NO_COLOR:-}" || "${TERM:-}" == "dumb" ]]; then
    color_flag="--no-color"
  fi

  local fzf_out
  fzf_out="$(printf '%s\n' "${fzf_items[@]}" | fzf \
    --multi \
    ${color_flag} \
    --reverse \
    --prompt="archforge > " \
    --header="[TAB]: Select/Deselect | [ENTER]: Apply | [ESC]: Cancel" \
    --pointer="❯" \
    --marker="✓ " \
    --preview="${preview_bin} --preview-module {1}" \
    --preview-window="right:52%:wrap" \
    2>/dev/null || true)"
  local ret=$?

  if [[ -z "${fzf_out}" || "${ret}" -eq 130 ]]; then
    SELECTED_MODULES=()
    return 0
  fi

  local -a raw_selected=()
  local sel_line sel_id
  while IFS= read -r sel_line; do
    [[ -z "${sel_line}" ]] && continue
    sel_id="${sel_line%% *}"
    [[ -n "${sel_id}" ]] && raw_selected+=("${sel_id}")
  done <<< "${fzf_out}"

  if [[ ${#raw_selected[@]} -gt 0 ]]; then
    local -a _reordered=()
    mapfile -t _reordered < <(_sort_by_execution_order "${raw_selected[@]}")
    SELECTED_MODULES=("${_reordered[@]}")
  fi
}

# ── Public Entry Point ────────────────────────────────────────────────────────
show_menu() {
  # shellcheck disable=SC2178
  local -n _module_list=$1
  SELECTED_MODULES=()

  if [[ ${#_module_list[@]} -eq 0 ]]; then
    log_warn "No modules available to select."
    return 0
  fi

  local engine
  engine="$(_detect_tui_engine)"

  case "${engine}" in
    d3)
      _show_menu_d3 _module_list
      ;;
    d1|*)
      _show_menu_d1 _module_list
      ;;
  esac
}
