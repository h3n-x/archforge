# Changelog

## [Unreleased]

### Added
- **AMD GPU Graphics Module**:
  - **amd.sh**: Open-source AMD driver suite (`mesa`, `vulkan-radeon`), early KMS loading (`MODULES=(... amdgpu)` in `/etc/mkinitcpio.conf`) with idempotency and backup protection, multilib 32-bit package installation for Steam/Wine, and GPU utilization monitoring (`nvtop`).
- **Intel Graphics Module**:
  - **intel.sh**: Open-source Intel driver suite (`mesa`, `vulkan-intel`), hardware video acceleration driver selection (`intel-media-driver` for Gen 8+ Broadwell through modern Arc vs `libva-intel-driver` for legacy Haswell), multilib 32-bit packages, early KMS support, and GPU monitoring (`intel-gpu-tools`).
- **Audio Module**:
  - **audio.sh**: Complete modern audio stack (`pipewire`, `pipewire-audio`, `pipewire-pulse`, `pipewire-alsa`, `wireplumber`), optional JACK replacement (`pipewire-jack`), optional GUI volume control (`pavucontrol`), and automatic activation of systemd user services (`pipewire.service`, `pipewire-pulse.service`, `wireplumber.service`) via `enable_user_service`.
- **Bluetooth Module**:
  - **bluetooth.sh**: Full BlueZ Bluetooth protocol stack (`bluez`, `bluez-utils`), optional GTK manager (`blueman`), system `bluetooth.service` activation, rfkill software-block detection and auto-unblock, and declared `MODULE_DEPENDS="audio"` with PipeWire audio integration checks.
- **Core Helpers & Multi-User Safety**:
  - **lib/core.sh**: Added `enable_user_service` to manage `systemctl --user` units safely across chroot/headless, single-user desktop, and multi-user environments with `loginctl` fallback; added `run_cmd_secret` to execute commands handling secrets without persisting credentials to disk.
- **TUI & ArchWiki Integration**:
  - Added D1/D3 dual-engine interactive selector with terminal geometry detection, automatic two-column responsive layout, and live ArchWiki documentation preview card in fzf.

## [0.3.0] - 2026-09-18

### Added
- **Wayland & Hyprland Support**:
  - **nvidia.sh**: Configured early KMS loading (`MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)` in `/etc/mkinitcpio.conf`), enabled `options nvidia_drm modeset=1 fbdev=1` in `/etc/modprobe.d/nvidia.conf`, created `/etc/environment.d/10-nvidia-wayland.conf` drop-in, and enforced `mkinitcpio -P` regeneration.
  - **libinput.sh**: Added generation of Hyprland input configuration snippet (`~/.config/hypr/conf.d/input.conf`) with tap-to-click, natural scrolling, and acceleration profile.
  - **fonts.sh**: Added `ttf-jetbrains-mono-nerd` package option for Waybar, Hyprland, and modern terminal icons.
  - **keyboard.sh**: Added Wayland and Hyprland keyboard layout configuration guidance.
- **Core Security & Execution Hardening**:
  - **lib/core.sh**: Added `start_sudo_keepalive` and `stop_sudo_keepalive` lifecycle helpers to avoid sudo timeouts during long tasks; added `validate_fstab` (with findmnt & column checks) and `validate_nftables` pre-write syntax validators.
  - **lib/backup.sh**: Elevated restore operations with `sudo` for root-owned destinations to prevent `Permission denied`; resolved real user home directory via `$SUDO_USER` in `_get_default_backup_base`; isolated `backup_file` under `DRY_RUN`.
  - **lib/packages.sh**: Prevented recording package installations to temporary logs during dry-run.

### Fixed
- **pacman.sh**: Replaced `pacman -Sy` with `pacman -Syu` to eliminate unsupported partial upgrade risks.
- **aur-helper.sh**: Migrated makepkg optimization options to `/etc/makepkg.conf.d/archforge-makepkg.conf` drop-in instead of mutating `/etc/makepkg.conf`.
- **users-groups.sh**: Omitted deprecated pre-systemd legacy groups (`audio`, `video`, `storage`, `optical`, `scanner`, `games`) per ArchWiki guidelines to preserve systemd-logind and PipeWire ACLs.
- **dns.sh**: Added `systemctl enable --now systemd-resolved` so stub resolver persists across reboots.
- **firewall.sh**: Pre-validated nftables syntax (`nft -c -f`) before loading and added conflict check for active `ufw`, `firewalld`, or `iptables.service`.
- **antivirus.sh**: Added `backup_file` tracking and `systemctl daemon-reload` for custom clamav unit files.
- **tlp.sh**: Automatically masks conflicting `power-profiles-daemon.service`.
- **acpid.sh**: Configured `HandleLidSwitch=ignore` in systemd-logind drop-in to prevent double-suspend race conditions.
- **performance.sh**: Moved `earlyoom` installation from AUR to official `[extra]` repository via pacman.
- **ssd.sh**: Fixed critical bug in awk script where the `/` root mount line was dropped from `/etc/fstab`; added `validate_fstab` pre-check.
- **nouveau.sh**: Removed obsolete `xf86-video-nouveau` DDX driver in favor of modesetting and mesa; corrected module name typo in mkinitcpio check.
- **steam.sh**: Migrated esync file descriptor limit to `/etc/security/limits.d/10-esync.conf` drop-in.
- **configs**: Updated header comments from legacy `# arch-rice` to `# archforge`.
- **docs**: Restored Spanish documentation parity for restore limitations in `README.es.md` and corrected ThinkPad/Lenovo battery threshold claims in module tables.

## [0.2.0] - 2026-03-22

### Added
- **steam.sh**: File descriptor limit raise (`/etc/security/limits.d/`) for esync/fsync; `/proc/sys/vm/max_map_count` configuration for large shader caches; `/etc/gamemode.ini` creation with CPU governor + renice settings; GameMode group membership check; MangoHud config file (`~/.config/MangoHud/MangoHud.conf`) with FPS cap, GPU/CPU stats, frametime graph
- **ssd.sh**: Full rewrite — `_verify_trim_support()` checks rotational flag + discard capability; `_check_luks()` warns if LUKS layer is missing `discard` in crypttab; `_configure_trim()` enables `fstrim.timer`; `_configure_continuous_trim()` adds `discard` mount option with XFS-incompatibility guard (falls back to timer); `_configure_tmpfs_tmp()` mounts `/tmp` as tmpfs; `_add_noatime_to_fstab()` adds `noatime` to ext4/btrfs/xfs entries
- **tlp.sh**: `_check_cpufreq_conflict()` detects and warns about `power-profiles-daemon` conflict; `_configure_battery_thresholds()` for start/stop charge thresholds (ThinkPad/Huawei); `_configure_usb_denylist()` to exclude peripherals from autosuspend
- **performance.sh**: `_configure_network_sysctls()` (rmem/wmem buffers, TCP fastopen, BBR); `_configure_thp()` with `defer+madvise` mode and systemd-tmpfiles unit; improved `_configure_zram()` writing swappiness=180 to separate `/etc/sysctl.d/99-vm-zram-parameters.conf` to override base vm.swappiness=10; `_configure_oom_killer()`, `_install_earlyoom()`, `_configure_systemd_oomd()`
- **aur-helper.sh**: AUR security warning (unreviewed PKGBUILD risk); `_optimize_makepkg()` — MAKEFLAGS=-j$(nproc), BUILDDIR tmpfs detection, COMPRESSZST multi-thread, `!debug !lto` OPTIONS, ccache detection and integration
- **network.sh**: `_configure_wifi_powersave()` via NetworkManager conf.d drop-in; `_configure_regulatory_domain()` installs `wireless-regdb`, edits `/etc/conf.d/wireless-regdom`, applies immediately with `iw reg set`; `_configure_mac_randomization()` shows current MACs via `nmcli` before prompting, writes stable/random conf.d drop-in
- **locale.sh**: `_uncomment_or_append_locale()` helper — uncomments existing commented entry or appends if absent; `en_US.UTF-8` added as fallback when non-US locale selected; `_configure_hardware_clock()` sets UTC/localtime standard via `timedatectl set-local-rtc` and syncs with `hwclock --systohc`; fixed `MODULE_WIKI_SOURCE`
- **systemd.sh**: Source lines added; `_configure_journal()` creates drop-in at `/etc/systemd/journald.conf.d/archforge.conf` with `Storage=persistent` and configurable `SystemMaxUse`; `_boot_analysis()` runs `systemd-analyze`, optional `blame` and `critical-chain`
- **pacman.sh**: Source lines added; reflector config uses temp file + `sudo cp` (replaces `sudo bash -c` heredoc antipattern); `_configure_keyring()` installs `archlinux-keyring` and runs `pacman-key --populate archlinux`; `_configure_pkgfile()` installs pkgfile, populates database, enables `pkgfile-update.timer` and `pacman-filesdb-refresh.timer`; `_configure_paccache()` enables `paccache.timer`
- **nftables-desktop.conf / nftables-server.conf**: SSH rate limiting rule (`ct state new limit rate 15/minute`); drop logging with `log prefix "nftables-drop: " flags all` before final drop; server profile: port 22 removed from OPEN_TCP_PORTS (now exclusively handled by rate-limit rule)
- **antivirus.sh**: `_configure_clamd()` applies all wiki-recommended `clamd.conf` settings (LogTime, ExtendedDetectionInfo, User clamav, DetectPUA, HeuristicAlerts, ScanPE/ELF/OLE2/PDF/HTML/Archive, AlertBrokenExecutables/Encrypted/OLE2Macros); `_configure_on_access_scan()` optional real-time scanning via clamd + clamonacc (OnAccessExcludeUname, OnAccessMountPath, OnAccessPrevention no, OnAccessExtraScanning yes); `MODULE_WIKI_SOURCE` corrected to `aur-wiki-clamav.txt`
- **firewall.sh**: Log viewer after activation — shows drop log via `journalctl -k --grep="nftables-drop"`; `MODULE_WIKI_SOURCE` updated

### Fixed
- **antivirus.sh**: Added `set -euo pipefail`, source lines, `module_info()` call, `BASH_SOURCE` guard — module was broken for standalone execution
- **users-groups.sh**: Added `set -euo pipefail` and `source` for `lib/core.sh` — functions (`run_cmd`, `log_*`, `confirm`) were undefined in standalone execution
- **dns.sh**: Added `set -euo pipefail`, source lines, `module_info()` call, `BASH_SOURCE` guard; "recomendado" → "recommended" in provider menu
- **acpid.sh**: `MODULE_WIKI_SOURCE` updated to include `aur-wiki-acpid.txt`
- **fonts.sh**: FONT= entry in vconsole.conf now uses `sed -i` to update existing line before appending, preventing duplicate `FONT=` entries on repeated runs
- **libinput.sh**: Added informational note after configuration — log lines clarify Xorg config path and that Wayland compositors (Hyprland/Sway) use per-compositor input settings instead

## [0.1.0] - 2026-03-22

### Changed
- **lib/menu.sh**: Remove fzf dependency entirely — replaced with native bash interactive menu; modules displayed in numbered table grouped by category (alphabetical), modules within each category sorted alphabetically; input accepts any combination of numbers, names, `all`, or `q`/empty to quit; `MODULE_BY_NUMBER` associative array maps number→module-id for O(1) lookup
- **lib/menu.sh**: Banner rewritten using `printf '%s\n'` strings (no heredoc); UTF-8 terminal detection — uses Unicode box-drawing frame (`╔═╗║╚╝`) when available, falls back to ASCII `+--+` border; version bumped to v0.1.0 in banner
- **archforge**: `ARCHFORGE_VERSION` bumped to `0.1.0`
- **README.md**: Full rewrite — centered header with shields.io badges; bilingual structure (ES/EN); expanded module table to 28 modules with ArchWiki links; `make install` quick-start; fzf removed from requirements
- **Repository**: Added `LICENSE` (MIT), `.gitignore`, `.editorconfig`, `CONTRIBUTING.md`, `Makefile` with `install`/`uninstall`/`lint`/`test`/`check` targets

## [0.1.3] - 2026-03-22

### Changed
- **lib/menu.sh**: Complete visual redesign — ASCII banner printed before fzf/fallback menu; fzf display format changed to `id  [Category]  name  —  description`; fzf options updated to Catppuccin color scheme with `--border=rounded`, `--layout=reverse`, `--header-first`, `a:select-all` bind; bash fallback now groups modules by category in box-drawing borders
- **archforge**: Module header redesigned — separator line `── Module: Name ──────` extends to column 60 (dynamic fill with `─`); `MODULE_HW_WARN` shown in yellow with `⚠` between separator and URLs; wiki URLs rendered in cyan without `[ INFO ]` prefix (pure decoration, not log messages); blank line after header before confirm prompt
- **lib/core.sh**: `confirm()` accepts optional `$2` default parameter — `"y"` renders `[Y/n]` and treats Enter as yes; `"n"` or omitted renders `[y/N]` and treats Enter as no (previous behavior)
- **41 `confirm` calls changed to default YES** across 19 modules: all standard safe actions (package installs, service enables, recommended config changes, fstab optimizations, DNS setup, locale, fonts, libinput, NFS mounts, printer drivers, gaming tools, user group additions, zram, sensors)
- **Module application gate** (`"Apply module: …?"`) changed to default YES — user already selected modules from menu
- **22 `confirm` calls kept at default NO**: HW_WARN modules (acpid, tlp — laptop-only), autologin (security), strict firewall profile, `chattr +i` immutable flag, NVIDIA driver installation gates, Nouveau driver switch (removes NVIDIA packages), VMware inside VM (risky nesting), Optimus env file (niche), error-path "Continue anyway?" guards

## [0.1.2] - 2026-03-22

### Fixed
- **locale.sh**: Drain buffered stdin before locale prompt to prevent stray `y` keystrokes from prior confirms; validate detected default locale with regex before using it as default (falls back to `en_US.UTF-8` if corrupted)
- **lib/backup.sh**: Add `[[ -r "${path}" ]]` check before `cp`; files existing but unreadable by current user now emit a warning and skip cleanly instead of crashing with Permission denied
- **performance.sh**: Suppress `sysctl --system` verbose output (40+ lines); show only `[INFO] sysctl parameters applied.` on success or `[ERROR]` with captured output on failure
- **sensors.sh**: Remove `pacman_install fancontrol` — `fancontrol` binary is already included in `lm_sensors` package; no separate install needed
- **network.sh**: Use `hostnamectl hostname` for persistent hostname read; add RFC 1123 validation — warn explicitly if current hostname is ≤1 char or invalid
- **sensors.sh**: Narrow `sensors-detect` grep filter to exclude `Client found at address 0x...` noise; show only chip names (`Found [A-Z]`), `Loaded`, `Handled by driver`, `Driver` lines
- **print_summary()**: Replace ad-hoc printf format strings with `box_line()` / `box_line_sub()` helper functions that guarantee `BOX_WIDTH-4` field width and truncate long content with `...`; fix manifest PATH regex to match leading whitespace
- **pacman.sh**: Warn at module start if packages were already installed this session (pkg log non-empty), recommending to run pacman module first
- **lib/packages.sh**: Check `pkg_installed()` per package before calling `pacman -S`; emit `[SKIP] pkg already installed` in grey and skip invocation entirely when all packages are already present

## [0.1.1] - 2026-03-22

### Fixed
- **locale.sh**: Validate locale input against `^[a-zA-Z_]+\.UTF-8$` before passing to `locale-gen`; loop back on invalid format; show current locale as default suggestion to prevent accidental garbage input
- **antivirus.sh**: Check if `clamav-freshclam.service` is active before updating signatures; use `systemctl restart` when active (avoids log lock conflict); use `systemctl enable --now` only when inactive
- **systemd.sh**: Filter `●` summary token from `systemctl --failed --no-legend` output; show `[OK] No failed systemd units.` in green when none found instead of `[WARN]` with a lone bullet
- **sensors.sh**: Suppress verbose `sensors-detect --auto` output; redirect to temp file and display only lines matching `Found|Loaded|added`; DRY_RUN/TEST modes still pass through `run_cmd`
- **fonts.sh**: Replace `fc-cache -fv` with `fc-cache -f` to eliminate verbose directory listing noise
- **print_summary()**: Fix box border misalignment — correct all `printf` field widths to sum to 54 (inner box width); truncate long `module_name`, package, path, and log file values at field boundary with `...`

## [0.0.1] - 2026-03-22

### Added
- 19 modules across 9 categories (package management, system services, security, power, networking, input, optimization, console, display)
- Interactive fzf multi-select menu with bash-select fallback
- Hardware detection (CPU, GPU, laptop/desktop via DMI)
- On-disk backup system with manifest and `restore` subcommand
- `--dry-run`, `--yes`, `--modules`, `--aur-helper` flags
- Session summary report saved to `~/.local/share/archforge/logs/`
- Shellcheck-clean codebase with bats-core test suite
- Bilingual documentation (ES/EN)
