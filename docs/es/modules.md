# Modulos de archforge

## Lista completa

| ID | Nombre | Descripcion | Fuente wiki | Paquetes |
|---|---|---|---|---|
| acpid | Power: ACPI events | Suspension al cerrar tapa, eventos de boton de encendido | [Acpid](https://wiki.archlinux.org/title/Acpid) [Gestion de energia](https://wiki.archlinux.org/title/Power_management) | acpid |
| amd | Graphics: AMD GPU (AMDGPU) | Driver AMD de código abierto (Mesa radeonsi, RADV vulkan-radeon), KMS temprano, multilib 32-bit opcional | [AMDGPU](https://wiki.archlinux.org/title/AMDGPU) | mesa vulkan-radeon |
| antivirus | Security: Antivirus | ClamAV con config de clamd, freshclam, escaneo en tiempo real opcional, timer semanal | [ClamAV](https://wiki.archlinux.org/title/ClamAV) | clamav |
| audio | Peripherals: Audio | Pila moderna de audio con PipeWire, emulación PulseAudio/ALSA, gestor de sesión WirePlumber, JACK y pavucontrol opcionales | [PipeWire](https://wiki.archlinux.org/title/PipeWire) [WirePlumber](https://wiki.archlinux.org/title/WirePlumber) | pipewire pipewire-audio pipewire-pulse pipewire-alsa wireplumber |
| aur-helper | Package Management: AUR helper | Detectar o instalar AUR helper (yay/paru), optimizar makepkg (MAKEFLAGS, BUILDDIR, ccache) | [AUR helpers](https://wiki.archlinux.org/title/AUR_helpers) [Makepkg](https://wiki.archlinux.org/title/Makepkg) | base-devel git |
| bluetooth | Peripherals: Bluetooth | Pila de protocolos BlueZ, CLI bluetoothctl, GUI blueman opcional, desbloqueo rfkill | [Bluetooth](https://wiki.archlinux.org/title/Bluetooth) | bluez bluez-utils |
| dns | Security: DNS | Proveedor DNS con deteccion de 4 casos (6 proveedores), DNSSEC, DNS-over-TLS | [Resolucion de nombres de dominio](https://wiki.archlinux.org/title/Domain_name_resolution) [DNSSEC](https://wiki.archlinux.org/title/DNSSEC) | — |
| firewall | Security: Firewall | Perfiles nftables (desktop/server/strict), rate limiting SSH, log de drops | [Nftables](https://wiki.archlinux.org/title/Nftables) [Iptables](https://wiki.archlinux.org/title/Iptables) | nftables |
| fonts | Console: Fonts | terminus-font, noto-fonts, ttf-liberation, JetBrains Mono Nerd Font, vconsole.conf | [Fuentes](https://wiki.archlinux.org/title/Fonts) [Consola Linux](https://wiki.archlinux.org/title/Linux_console) [Fuentes metric-compatibles](https://wiki.archlinux.org/title/Metric-compatible_fonts) | terminus-font noto-fonts noto-fonts-emoji ttf-liberation ttf-jetbrains-mono-nerd |
| intel | Graphics: Intel Graphics | Driver Intel de código abierto (Mesa iris/crocus, ANV vulkan-intel), aceleración VA-API (intel-media-driver), multilib 32-bit opcional | [Intel graphics](https://wiki.archlinux.org/title/Intel_graphics) | mesa vulkan-intel intel-media-driver |
| keyboard | Input: Keyboard | Keymap de consola, layout X11 via localectl | [Xorg/Teclado](https://wiki.archlinux.org/title/Xorg/Keyboard_configuration) [Consola Linux/Teclado](https://wiki.archlinux.org/title/Linux_console/Keyboard_configuration) | — |
| libinput | Input: libinput | Touchpad, scroll natural, TrackPoint, snippet de configuracion para Wayland/Hyprland | [Libinput](https://wiki.archlinux.org/title/Libinput) [TrackPoint](https://wiki.archlinux.org/title/TrackPoint) [Botones del raton](https://wiki.archlinux.org/title/Mouse_buttons) | — |
| locale | Console: Locale | locale-gen, zona horaria, sincronizacion de reloj hardware, NTP | [Locale](https://wiki.archlinux.org/title/Locale) [Hora del sistema](https://wiki.archlinux.org/title/System_time) | — |
| network | Networking: Network | Hostname, /etc/hosts, NetworkManager, ahorro WiFi, dominio regulatorio, MAC aleatoria | [Configuracion de red](https://wiki.archlinux.org/title/Network_configuration) [NetworkManager](https://wiki.archlinux.org/title/NetworkManager) | wireless-regdb |
| nouveau | Graphics: Nouveau | Driver NVIDIA libre (modesetting + mesa); quitar propietario si aplica | [Nouveau](https://wiki.archlinux.org/title/Nouveau) | mesa |
| nvidia | Graphics: NVIDIA | Driver NVIDIA propietario u open, KMS temprano, Wayland fbdev, Optimus opcional | [NVIDIA](https://wiki.archlinux.org/title/NVIDIA) [NVIDIA Optimus](https://wiki.archlinux.org/title/NVIDIA_Optimus) [GPU](https://wiki.archlinux.org/title/Graphics_processing_unit) | (paquetes segun eleccion en runtime) |
| pacman | Package: Pacman | Configurar pacman.conf, multilib, reflector, keyring, pkgfile, paccache | [Pacman](https://wiki.archlinux.org/title/Pacman) [Pacman/Tips and tricks](https://wiki.archlinux.org/title/Pacman/Tips_and_tricks) | pacman-contrib reflector pkgfile |
| performance | Optimization: Performance | Sysctls de red, THP, zram, OOM killer (earlyoom/systemd-oomd), gobernador CPU | [Rendimiento](https://wiki.archlinux.org/title/Improving_performance) [Zram](https://wiki.archlinux.org/title/Zram) | zram-generator earlyoom |
| printing | Peripherals: Printing | CUPS, SANE opcional, drivers de impresora | [CUPS](https://wiki.archlinux.org/title/CUPS) [CUPS/Solucion de problemas](https://wiki.archlinux.org/title/CUPS/Troubleshooting) | cups cups-pdf |
| sensors | Optimization: Sensors | lm_sensors, deteccion de sensores | [Lm sensors](https://wiki.archlinux.org/title/Lm_sensors) [Control de ventiladores](https://wiki.archlinux.org/title/Fan_speed_control) | lm_sensors |
| ssd | Optimization: SSD | Verificar TRIM, fstrim timer, discard continuo, noatime, tmpfs /tmp | [Unidad de estado solido](https://wiki.archlinux.org/title/Solid_state_drive) | — |
| steam | Gaming: Steam | Steam, deps Proton/Wine, fd-limit, max_map_count, GameMode, MangoHud | [Steam](https://wiki.archlinux.org/title/Steam) [Steam/Solucion de problemas](https://wiki.archlinux.org/title/Steam/Troubleshooting) | steam gamemode lib32-gamemode |
| systemd | System Services: systemd | Journal persistente (drop-in), analisis de arranque (systemd-analyze), timesyncd | [Systemd](https://wiki.archlinux.org/title/Systemd) [Systemd/Journal](https://wiki.archlinux.org/title/Systemd/Journal) | — |
| tlp | Power: TLP | Optimizacion de bateria, umbrales de carga (ThinkPad/Lenovo), lista de exclusion USB | [TLP](https://wiki.archlinux.org/title/TLP) [Laptop](https://wiki.archlinux.org/title/Laptop) | tlp |
| users-groups | System: Users and Groups | Agregar usuario a grupos habituales (wheel, docker, libvirt, etc.) | [Usuarios y grupos](https://wiki.archlinux.org/title/Users_and_groups) | — |
| vmware-host | Virtualization: VMware | Host VMware Workstation Pro (AUR) | [VMware](https://wiki.archlinux.org/title/VMware) | vmware-workstation (AUR) |

&nbsp;

## Perfiles del Sistema

`archforge` incluye 4 perfiles predefinidos accesibles mediante `--profile=NOMBRE`. Cada perfil agrupa una base de software independiente del hardware y aplica una resolución automática basada en el hardware detectado:

| Perfil | Objetivo / Caso de uso | Módulos base de software |
|---|---|---|
| `server` | Servidores headless, VPS o Home Labs | `pacman`, `aur-helper`, `systemd`, `users-groups`, `network`, `dns`, `firewall`, `antivirus`, `locale`, `ssd`, `performance` |
| `desktop-minimal` | Base ligera de escritorio / TWM (Hyprland, Sway, i3) | `pacman`, `aur-helper`, `systemd`, `users-groups`, `network`, `dns`, `firewall`, `keyboard`, `locale`, `fonts`, `libinput`, `audio`, `ssd`, `performance` |
| `desktop-full` | Estación de trabajo diaria completa | `desktop-minimal` + `bluetooth`, `printing` |
| `gaming` | PCs optimizadas para juegos | `pacman`, `aur-helper`, `network`, `dns`, `firewall`, `keyboard`, `locale`, `fonts`, `libinput`, `audio`, `bluetooth`, `ssd`, `performance`, `steam` |

### Resolución Dinámica Consciente del Hardware

A menos que se indique `--no-hardware-detect`, `archforge` escanea el equipo dinámicamente:
- **Escaneo Multi-GPU en el bus PCI**: Interroga los controladores de pantalla y 3D en PCI (`lspci`), añadiendo `amd`, `intel` o `nvidia` según corresponda. En portátiles híbridos (p. ej. APU AMD integrada + NVIDIA discreta), ambos controladores se configuran sin conflicto.
- **Detección Rigurosa de Portátiles**: Inspecciona `/sys/class/power_supply` (verificando `type == Battery` y excluyendo `scope == Device` de periféricos) y `hostnamectl chassis` para inyectar `tlp` y `acpid` exclusivamente en portátiles reales.
- **Bare-metal vs Máquina Virtual**: Comprueba el estado de virtualización mediante `systemd-detect-virt`, inyectando `sensors` en hardware físico y omitiéndolo limpiamente dentro de máquinas virtuales.
- **Composición y Ordenamiento**: Los módulos extra añadidos mediante `--modules` se fusionan, desduplican y ordenan canónicamente según el orden seguro de ejecución.

