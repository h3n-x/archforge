#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true DRY_RUN=false
  # shellcheck disable=SC1091
  source "${ARCHFORGE_DIR}/lib/core.sh"
  # shellcheck disable=SC1091
  source "${ARCHFORGE_DIR}/lib/packages.sh"
  # shellcheck disable=SC1091
  source "${ARCHFORGE_DIR}/lib/backup.sh"
  # shellcheck disable=SC1091
  source "${ARCHFORGE_DIR}/modules/07-optimization/ssd.sh"
  mock_reset
}

@test "ssd _add_noatime_to_fstab idempotent when noatime already present" {
  local tmp; tmp="$(mktemp)"
  echo "UUID=abc / ext4 defaults,noatime 0 1" > "${tmp}"
  _add_noatime_to_fstab "${tmp}"
  run grep -c "noatime" "${tmp}"
  [ "${output}" -eq 1 ]
  rm "${tmp}"
}

@test "ssd _add_noatime_to_fstab adds noatime to defaults" {
  local tmp; tmp="$(mktemp)"
  echo "UUID=abc / ext4 defaults 0 1" > "${tmp}"
  _add_noatime_to_fstab "${tmp}"
  run grep "noatime" "${tmp}"
  [ "${status}" -eq 0 ]
  rm "${tmp}"
}

@test "ssd _add_noatime_to_fstab handles UUID device format" {
  local tmp; tmp="$(mktemp)"
  echo "UUID=1234-5678 / ext4 defaults 0 1" > "${tmp}"
  _add_noatime_to_fstab "${tmp}"
  run grep "noatime" "${tmp}"
  [ "${status}" -eq 0 ]
  rm "${tmp}"
}

@test "ssd _add_noatime_to_fstab does not modify non-root mounts" {
  local tmp; tmp="$(mktemp)"
  echo "UUID=abc /home ext4 defaults 0 2" > "${tmp}"
  _add_noatime_to_fstab "${tmp}"
  run grep "noatime" "${tmp}"
  [ "${status}" -ne 0 ]
  rm "${tmp}"
}

@test "regression(ssd): _add_noatime_to_fstab explicitly preserves root / line in multi-entry fstab" {
  local tmp; tmp="$(mktemp)"
  cat > "${tmp}" <<'EOF'
# /etc/fstab: static file system information.
UUID=1111-2222 /boot/efi vfat umask=0077 0 2
UUID=4a5b6c7d-8e9f-0123-4567-89abcdef0123 / ext4 defaults 0 1
UUID=9999-8888 /home btrfs subvol=@home,defaults 0 2
/swapfile none swap defaults 0 0
EOF

  _add_noatime_to_fstab "${tmp}"

  # 1. Root / line must be explicitly present
  run grep -E '^UUID=4a5b6c7d-8e9f-0123-4567-89abcdef0123[[:space:]]+/[[:space:]]+ext4' "${tmp}"
  [ "${status}" -eq 0 ]

  # 2. Options must have 'defaults,noatime'
  run awk '$2 == "/" {print $4}' "${tmp}"
  [ "${output}" = "defaults,noatime" ]

  # 3. All other entries must be intact
  run grep -c '^UUID=' "${tmp}"
  [ "${output}" -eq 3 ]
  run grep -q '/boot/efi' "${tmp}"
  [ "${status}" -eq 0 ]
  run grep -q '/home' "${tmp}"
  [ "${status}" -eq 0 ]
  run grep -q '/swapfile' "${tmp}"
  [ "${status}" -eq 0 ]

  rm -f "${tmp}"
}

@test "regression(ssd): _add_discard_to_fstab explicitly preserves root / line in multi-entry fstab" {
  local tmp; tmp="$(mktemp)"
  cat > "${tmp}" <<'EOF'
# /etc/fstab: static file system information.
UUID=1111-2222 /boot/efi vfat umask=0077 0 2
UUID=4a5b6c7d-8e9f-0123-4567-89abcdef0123 / ext4 defaults 0 1
UUID=9999-8888 /home btrfs subvol=@home,defaults 0 2
/swapfile none swap defaults 0 0
EOF

  _add_discard_to_fstab "${tmp}"

  # 1. Root / line must be explicitly present
  run grep -E '^UUID=4a5b6c7d-8e9f-0123-4567-89abcdef0123[[:space:]]+/[[:space:]]+ext4' "${tmp}"
  [ "${status}" -eq 0 ]

  # 2. Options must have 'defaults,discard'
  run awk '$2 == "/" {print $4}' "${tmp}"
  [ "${output}" = "defaults,discard" ]

  # 3. All other entries must be intact
  run grep -c '^UUID=' "${tmp}"
  [ "${output}" -eq 3 ]
  run grep -q '/boot/efi' "${tmp}"
  [ "${status}" -eq 0 ]
  run grep -q '/home' "${tmp}"
  [ "${status}" -eq 0 ]

  rm -f "${tmp}"
}

@test "ssd _add_discard_to_fstab idempotent when discard already present" {
  local tmp; tmp="$(mktemp)"
  echo "UUID=abc / ext4 defaults,discard 0 1" > "${tmp}"
  _add_discard_to_fstab "${tmp}"
  run grep -c "discard" "${tmp}"
  [ "${output}" -eq 1 ]
  rm -f "${tmp}"
}

@test "ssd _add_discard_to_fstab does not modify non-root mounts" {
  local tmp; tmp="$(mktemp)"
  echo "UUID=abc /home ext4 defaults 0 2" > "${tmp}"
  _add_discard_to_fstab "${tmp}"
  run grep "discard" "${tmp}"
  [ "${status}" -ne 0 ]
  rm -f "${tmp}"
}
