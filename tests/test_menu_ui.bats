#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true
  source "${ARCHFORGE_DIR}/lib/core.sh"
  source "${ARCHFORGE_DIR}/lib/menu.sh"
  mock_reset
}

# ── Engine Detection Tests (Requirements 3a - 3e) ─────────────────────────────

@test "engine detection: (a) non-TTY environment returns 'none'" {
  # In bats test runner, stdin is not an interactive terminal
  run _detect_tui_engine
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "engine detection: (b) ARCHFORGE_TUI=classic forced returns 'd1'" {
  ARCHFORGE_TEST_TTY=true ARCHFORGE_TUI=classic run _detect_tui_engine
  [ "$status" -eq 0 ]
  [ "$output" = "d1" ]
}

@test "engine detection: (c) fzf absent from PATH returns 'd1'" {
  ARCHFORGE_TEST_TTY=true PATH="/empty-bin-dir" run _detect_tui_engine
  [ "$status" -eq 0 ]
  [ "$output" = "d1" ]
}

@test "engine detection: (d) fzf present with --preview and geometry >= 80x20 returns 'd3'" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/fzf" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--help" ]]; then
  echo "Usage: fzf [options]"
  echo "  --preview=COMMAND  Command to preview current line"
  exit 0
fi
exit 0
EOF
  chmod +x "${fake_bin}/fzf"

  PATH="${fake_bin}:${PATH}" ARCHFORGE_TEST_TTY=true COLUMNS=100 LINES=30 run _detect_tui_engine
  [ "$status" -eq 0 ]
  [ "$output" = "d3" ]

  rm -rf "${fake_bin}"
}

@test "engine detection: (e) terminal < 80x20 degrades to 'd1' even if fzf is present" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/fzf" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--help" ]]; then
  echo "  --preview=COMMAND"
  exit 0
fi
exit 0
EOF
  chmod +x "${fake_bin}/fzf"

  # Width < 80
  PATH="${fake_bin}:${PATH}" ARCHFORGE_TEST_TTY=true COLUMNS=70 LINES=30 run _detect_tui_engine
  [ "$status" -eq 0 ]
  [ "$output" = "d1" ]

  # Height < 20
  PATH="${fake_bin}:${PATH}" ARCHFORGE_TEST_TTY=true COLUMNS=100 LINES=15 run _detect_tui_engine
  [ "$status" -eq 0 ]
  [ "$output" = "d1" ]

  rm -rf "${fake_bin}"
}

@test "engine detection: fzf legacy without --preview degrades to 'd1'" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/fzf" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--help" ]]; then
  echo "Usage: fzf 0.10.0 (legacy without preview support)"
  exit 0
fi
exit 0
EOF
  chmod +x "${fake_bin}/fzf"

  PATH="${fake_bin}:${PATH}" ARCHFORGE_TEST_TTY=true COLUMNS=100 LINES=30 run _detect_tui_engine
  [ "$status" -eq 0 ]
  [ "$output" = "d1" ]

  rm -rf "${fake_bin}"
}

# ── Preview Subcommand Tests (Requirement 2) ──────────────────────────────────

@test "preview_module: produces card with ArchWiki URLs for nvidia" {
  run preview_module "nvidia"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Graphics: NVIDIA driver" ]]
  [[ "$output" =~ "https://wiki.archlinux.org/title/NVIDIA" ]]
  [[ "$output" =~ "NVIDIA GPU required" ]]
}

@test "preview_module: includes hardware warning for tlp" {
  run preview_module "tlp"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Power: TLP" ]]
  [[ "$output" =~ "Designed for laptops" ]]
}

@test "preview_module: returns 1 for non-existent module" {
  run preview_module "nonexistent-xyz-module"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Module not found" ]]
}

@test "security: preview_module rejects absolute path outside modules/ (e.g. /etc/passwd)" {
  run preview_module "/etc/passwd"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Module not found" ]]
}

@test "security: preview_module rejects path traversal with ../ outside modules/" {
  run preview_module "../../etc/passwd"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Module not found" ]]
}

@test "security: preview_module rejects arbitrary script outside modules/ without sourcing it" {
  local evil_script="/tmp/evil_test_$$.sh"
  local canary_file="/tmp/evil_canary_$$.txt"
  rm -f "${canary_file}"
  cat <<EOF > "${evil_script}"
touch "${canary_file}"
module_info() { MODULE_NAME="Evil"; }
EOF
  chmod +x "${evil_script}"

  run preview_module "${evil_script}"
  rm -f "${evil_script}"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "Module not found" ]]
  [ ! -f "${canary_file}" ]
  rm -f "${canary_file}"
}


# ── NO_COLOR and TERM=dumb Standards Compliance (Requirement 4) ───────────────

@test "NO_COLOR: strips all ANSI escape sequences from D1 menu output" {
  local -a sample_entries=("nvidia:Graphics: NVIDIA driver:Install driver:NVIDIA GPU required")
  declare -A by_num=()
  declare -a all_ids=()

  NO_COLOR=1 COLUMNS=80 run _build_and_print_module_table sample_entries by_num all_ids
  [ "$status" -eq 0 ]
  # Assert no ANSI escape character \033 exists anywhere in output
  [[ "$output" != *$'\033'* ]]
}

@test "TERM=dumb: strips all ANSI escape sequences from D1 menu output" {
  local -a sample_entries=("nvidia:Graphics: NVIDIA driver:Install driver:NVIDIA GPU required")
  declare -A by_num=()
  declare -a all_ids=()

  TERM=dumb COLUMNS=80 run _build_and_print_module_table sample_entries by_num all_ids
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
}

# ── Dynamic Layout Columns (Requirement 1) ────────────────────────────────────

@test "D1 layout: COLUMNS < 90 outputs single column with descriptions" {
  local -a sample_entries=(
    "pacman:Package Management: Pacman:Base system update:"
    "nvidia:Graphics: NVIDIA:Install driver:NVIDIA GPU required"
  )
  declare -A by_num=()
  declare -a all_ids=()

  COLUMNS=80 run _build_and_print_module_table sample_entries by_num all_ids
  [ "$status" -eq 0 ]
  # Single column rows include the em-dash and description
  [[ "$output" =~ "— Base system update" ]]
  [[ "$output" =~ "— Install driver" ]]
}

@test "D1 layout: COLUMNS >= 90 outputs two columns without overflowing" {
  local -a sample_entries=(
    "pacman:Package Management: Pacman:Base system update:"
    "aur-helper:Package Management: AUR:Install yay:"
    "systemd:System Services: Systemd:Service tuning:"
    "nvidia:Graphics: NVIDIA:Install driver:NVIDIA GPU required"
  )
  declare -A by_num=()
  declare -a all_ids=()

  COLUMNS=100 run _build_and_print_module_table sample_entries by_num all_ids
  [ "$status" -eq 0 ]
  # Left column 1, right column 3 on same line
  [[ "$output" =~ "[ 1]" ]]
  [[ "$output" =~ "[ 3]" ]]
}

# ── Alphabetical Module Ordering & Number Mapping Tests ───────────────────────

@test "alphabetical ordering: ALL_MODULES in archforge is strictly sorted alphabetically from A to Z" {
  source "$ARCHFORGE_DIR/archforge" --parse-only
  [ "${#ALL_MODULES[@]}" -eq 26 ]

  local prev=""
  local entry id
  for entry in "${ALL_MODULES[@]}"; do
    id="${entry%%:*}"
    if [[ -n "${prev}" ]]; then
      # Strict alphabetical comparison
      if [[ ! "${prev}" < "${id}" ]]; then
        echo "Module '${id}' is not in alphabetical order after '${prev}'" >&2
        return 1
      fi
    fi
    prev="${id}"
  done
}

@test "menu numbering: each number 1 to 26 maps to the exact alphabetical module" {
  source "$ARCHFORGE_DIR/archforge" --parse-only

  local -a expected_order=(
    "acpid"
    "amd"
    "antivirus"
    "audio"
    "aur-helper"
    "bluetooth"
    "dns"
    "firewall"
    "fonts"
    "intel"
    "keyboard"
    "libinput"
    "locale"
    "network"
    "nouveau"
    "nvidia"
    "pacman"
    "performance"
    "printing"
    "sensors"
    "ssd"
    "steam"
    "systemd"
    "tlp"
    "users-groups"
    "vmware-host"
  )

  local -a menu_entries=()
  local entry id
  for entry in "${ALL_MODULES[@]}"; do
    id="${entry%%:*}"
    menu_entries+=("${id}:Category: ${id}:Description of ${id}:")
  done

  declare -A by_number=()
  declare -a all_ids=()
  _build_and_print_module_table menu_entries by_number all_ids 2>/dev/null

  [ "${#by_number[@]}" -eq 26 ]

  local i expected_id actual_id
  for (( i=1; i<=26; i++ )); do
    expected_id="${expected_order[$(( i - 1 ))]}"
    actual_id="${by_number[${i}]}"
    [ "${actual_id}" = "${expected_id}" ]
  done
}

@test "menu resolution: selecting numbers (1 4 17 26) resolves to expected alphabetical modules" {
  source "$ARCHFORGE_DIR/archforge" --parse-only

  local -a menu_entries=()
  local entry id
  for entry in "${ALL_MODULES[@]}"; do
    id="${entry%%:*}"
    menu_entries+=("${id}:Category: ${id}:Description of ${id}:")
  done

  # 1 = acpid, 4 = audio, 17 = pacman, 26 = vmware-host
  SELECTED_MODULES=()
  _show_menu_d1 menu_entries <<< "1 4 17 26" 2>/dev/null

  # Verify all 4 are selected
  [ "${#SELECTED_MODULES[@]}" -eq 4 ]
  local out=" ${SELECTED_MODULES[*]} "
  [[ "$out" == *" acpid "* ]]
  [[ "$out" == *" audio "* ]]
  [[ "$out" == *" pacman "* ]]
  [[ "$out" == *" vmware-host "* ]]

  # Verify execution order sort puts pacman first and vmware-host last
  [ "${SELECTED_MODULES[0]}" = "pacman" ]
  [ "${SELECTED_MODULES[3]}" = "vmware-host" ]
}

@test "menu resolution: selecting numeric range 1-3 resolves to acpid, amd, and antivirus" {
  source "$ARCHFORGE_DIR/archforge" --parse-only

  local -a menu_entries=()
  local entry id
  for entry in "${ALL_MODULES[@]}"; do
    id="${entry%%:*}"
    menu_entries+=("${id}:Category: ${id}:Description of ${id}:")
  done

  SELECTED_MODULES=()
  _show_menu_d1 menu_entries <<< "1-3" 2>/dev/null

  [ "${#SELECTED_MODULES[@]}" -eq 3 ]
  local out=" ${SELECTED_MODULES[*]} "
  [[ "$out" == *" acpid "* ]]
  [[ "$out" == *" amd "* ]]
  [[ "$out" == *" antivirus "* ]]
}
