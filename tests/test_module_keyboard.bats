#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true DRY_RUN=false YES_FLAG=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  source "$ARCHFORGE_DIR/modules/06-input/keyboard.sh"
  mock_reset
}

@test "keyboard module_info exposes metadata and official ArchWiki sources" {
  module_info
  [ -n "${MODULE_NAME}" ]
  [[ "${MODULE_WIKI_SOURCE}" == *"aur-wiki-xorg-keyboard-configuration.txt"* ]]
  [[ "${MODULE_WIKI_SOURCE}" == *"aur-wiki-linux-console-keyboard-configuration.txt"* ]]
}

@test "keyboard module_run displays current localectl status" {
  local fake_bin; fake_bin="$(mktemp -d)"
  cat > "${fake_bin}/localectl" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "status" ]]; then
  echo "   System Locale: LANG=en_US.UTF-8"
  echo "       VC Keymap: us"
  echo "      X11 Layout: us"
  exit 0
fi
EOF
  chmod +x "${fake_bin}/localectl"

  PATH="${fake_bin}:${PATH}" run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"VC Keymap: us"* ]]
  [[ "$output" == *"X11 Layout: us"* ]]

  rm -rf "${fake_bin}"
}

@test "keyboard module_run logs Hyprland and Wayland instructions" {
  run module_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Wayland compositors (Hyprland, Sway)"* ]]
  [[ "$output" == *"kb_layout"* ]]
}

@test "keyboard module_run in non-test mode applies console keymap from input" {
  local fake_bin; fake_bin="$(mktemp -d)"
  local log_file; log_file="$(mktemp)"
  cat > "${fake_bin}/localectl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${fake_bin}/sudo" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${log_file}"
EOF
  chmod +x "${fake_bin}/localectl" "${fake_bin}/sudo"

  # Provide console keymap 'es' and empty X11 layout
  run bash -c "printf 'es\n\n' | ( export PATH='${fake_bin}:'\"\$PATH\" ARCHFORGE_DIR='$ARCHFORGE_DIR' ARCHFORGE_TEST=false DRY_RUN=false YES_FLAG=false; source '$ARCHFORGE_DIR/lib/core.sh'; source '$ARCHFORGE_DIR/modules/06-input/keyboard.sh'; module_run )"
  [ "$status" -eq 0 ]
  grep -q "localectl set-keymap es" "${log_file}"

  rm -rf "${fake_bin}" "${log_file}"
}

@test "keyboard module_run in non-test mode applies X11 layout and variant" {
  local fake_bin; fake_bin="$(mktemp -d)"
  local log_file; log_file="$(mktemp)"
  cat > "${fake_bin}/localectl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${fake_bin}/sudo" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${log_file}"
EOF
  chmod +x "${fake_bin}/localectl" "${fake_bin}/sudo"

  # Provide empty console keymap, X11 layout 'es', X11 variant 'dvorak'
  run bash -c "printf '\nes\ndvorak\n' | ( export PATH='${fake_bin}:'\"\$PATH\" ARCHFORGE_DIR='$ARCHFORGE_DIR' ARCHFORGE_TEST=false DRY_RUN=false YES_FLAG=false; source '$ARCHFORGE_DIR/lib/core.sh'; source '$ARCHFORGE_DIR/modules/06-input/keyboard.sh'; module_run )"
  [ "$status" -eq 0 ]
  grep -q "localectl set-x11-keymap es  dvorak" "${log_file}"

  rm -rf "${fake_bin}" "${log_file}"
}

@test "keyboard module_run skips execution when all inputs are blank" {
  local fake_bin; fake_bin="$(mktemp -d)"
  local log_file; log_file="$(mktemp)"
  cat > "${fake_bin}/localectl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${fake_bin}/sudo" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${log_file}"
EOF
  chmod +x "${fake_bin}/localectl" "${fake_bin}/sudo"

  # Blank console keymap, blank X11 layout
  run bash -c "printf '\n\n' | ( export PATH='${fake_bin}:'\"\$PATH\" ARCHFORGE_DIR='$ARCHFORGE_DIR' ARCHFORGE_TEST=false DRY_RUN=false YES_FLAG=false; source '$ARCHFORGE_DIR/lib/core.sh'; source '$ARCHFORGE_DIR/modules/06-input/keyboard.sh'; module_run )"
  [ "$status" -eq 0 ]
  [ ! -s "${log_file}" ]

  rm -rf "${fake_bin}" "${log_file}"
}

