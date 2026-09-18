#!/usr/bin/env bats
load 'setup'

setup() {
  export ARCHFORGE_TEST=true
  source "$ARCHFORGE_DIR/lib/core.sh"
  source "$ARCHFORGE_DIR/lib/packages.sh"
  source "$ARCHFORGE_DIR/lib/backup.sh"
  mock_reset
}

@test "pacman.sh does not run unsupported pacman -Sy partial upgrades" {
  # ArchWiki: https://wiki.archlinux.org/title/System_maintenance#Partial_upgrades_are_unsupported
  run grep -E 'run_cmd.*pacman -Sy\b' "$ARCHFORGE_DIR/modules/01-package-management/pacman.sh"
  [ "$status" -ne 0 ]
}

@test "users-groups.sh does not offer deprecated pre-systemd groups" {
  # ArchWiki: https://wiki.archlinux.org/title/Users_and_groups#Pre-systemd_groups
  # Users should not be offered audio, video, storage, optical, scanner, games
  run grep -E '"(audio|video|storage|optical|scanner|games)\|' "$ARCHFORGE_DIR/modules/02-system-services/users-groups.sh"
  [ "$status" -ne 0 ]
}

@test "tlp.sh handles power-profiles-daemon conflict" {
  # ArchWiki: https://wiki.archlinux.org/title/TLP#Conflicts
  run grep -q 'power-profiles-daemon' "$ARCHFORGE_DIR/modules/04-power/tlp.sh"
  [ "$status" -eq 0 ]
}

@test "acpid.sh configures systemd-logind drop-in to prevent double suspend" {
  # ArchWiki: https://wiki.archlinux.org/title/Acpid
  run grep -q 'HandleLidSwitch=ignore' "$ARCHFORGE_DIR/modules/04-power/acpid.sh"
  [ "$status" -eq 0 ]
  run grep -q 'backup_file.*archforge-lid' "$ARCHFORGE_DIR/modules/04-power/acpid.sh"
  [ "$status" -eq 0 ]
}

@test "earlyoom is installed via official pacman repo, not AUR" {
  # ArchWiki: https://wiki.archlinux.org/title/Improving_performance#Earlyoom
  # earlyoom is in official [extra]
  run grep -q 'pacman_install earlyoom' "$ARCHFORGE_DIR/modules/07-optimization/performance.sh"
  [ "$status" -eq 0 ]
  run grep -q 'aur_install earlyoom' "$ARCHFORGE_DIR/modules/07-optimization/performance.sh"
  [ "$status" -ne 0 ]
}

@test "nouveau.sh does not install obsolete xf86-video-nouveau DDX driver by default" {
  # ArchWiki: https://wiki.archlinux.org/title/Nouveau
  source "$ARCHFORGE_DIR/modules/10-graphics/nouveau.sh"
  module_info
  [[ "$MODULE_PACKAGES" != *"xf86-video-nouveau"* ]]
  [[ "$MODULE_PACKAGES" == *"mesa"* ]]
}

@test "steam.sh uses drop-in in limits.d for esync instead of limits.conf" {
  # ArchWiki: https://wiki.archlinux.org/title/Limits.conf
  run grep -q '/etc/security/limits.d/' "$ARCHFORGE_DIR/modules/11-gaming/steam.sh"
  [ "$status" -eq 0 ]
}

@test "dns.sh enables systemd-resolved service for persistence across reboots" {
  # ArchWiki: https://wiki.archlinux.org/title/Systemd-resolved
  run grep -q 'systemctl enable --now systemd-resolved' "$ARCHFORGE_DIR/modules/03-security/dns.sh"
  [ "$status" -eq 0 ]
}
