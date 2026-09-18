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
