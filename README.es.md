<h3 align="center">
  <img src="https://raw.githubusercontent.com/catppuccin/catppuccin/main/assets/misc/transparent.png" height="30" width="0"/>
  ARCHFORGE
  <img src="https://raw.githubusercontent.com/catppuccin/catppuccin/main/assets/misc/transparent.png" height="30" width="0"/>
  <br/>
  <a href="https://github.com/h3n-x/archforge">Toolkit modular de post-instalación para Arch Linux</a>
  <br/><br/>
  <p>
    🌐 <a href="README.md">English</a> · <strong>Español</strong>
  </p>
</h3>

<p align="center">
  <a href="https://github.com/h3n-x/archforge/stargazers"><img src="https://img.shields.io/github/stars/h3n-x/archforge?style=for-the-badge&logo=github&color=cba6f7&logoColor=d9e0ee&labelColor=363a4f" alt="Stars"/></a>
  <a href="https://github.com/h3n-x/archforge/issues"><img src="https://img.shields.io/github/issues/h3n-x/archforge?style=for-the-badge&color=cba6f7&logoColor=d9e0ee&labelColor=363a4f" alt="Issues"/></a>
  <a href="https://github.com/h3n-x/archforge/graphs/contributors"><img src="https://img.shields.io/github/contributors/h3n-x/archforge?style=for-the-badge&color=cba6f7&logoColor=d9e0ee&labelColor=363a4f" alt="Contributors"/></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/shell-bash-89dceb?style=for-the-badge&labelColor=363a4f" alt="Shell"/>
  <img src="https://img.shields.io/badge/license-MIT-a6e3a1?style=for-the-badge&labelColor=363a4f" alt="Licencia"/>
  <img src="https://img.shields.io/badge/version-0.2.0-cba6f7?style=for-the-badge&labelColor=363a4f" alt="Versión"/>
  <img src="https://img.shields.io/badge/platform-Arch%20Linux-74c7ec?style=for-the-badge&labelColor=363a4f" alt="Plataforma"/>
</p>

<p align="center">
  <a href="docs/es/modules.md">Referencia de módulos</a>
  ·
  <a href="CONTRIBUTING.md">Contribuir</a>
  ·
  <a href="https://github.com/h3n-x/archforge/blob/main/LICENSE">Licencia</a>
</p>

&nbsp;

## 🪄 Acerca de

`archforge` automatiza la configuración de un sistema **Arch Linux** recién instalado. Ejecuta **módulos** independientes que configuran paquetes, servicios, seguridad, red, rendimiento, entrada, consola, gráficos y más. Cada archivo que `archforge` edita o crea se **respalda** automáticamente y puede revertirse con `archforge restore` — incluyendo la reversión de archivos creados desde cero, no solo la restauración de los sobrescritos. Las instalaciones de paquetes y los cambios de estado de servicios/grupos (`systemctl enable`, `usermod`, etc.) se aplican directamente y **no** son revertidos por `restore`; el resumen impreso tras cada ejecución lista los paquetes instalados para que puedas eliminarlos manualmente si lo necesitas.

> [!NOTE]
> **Solo ArchWiki (oficial):** Los textos de este readme, las descripciones de módulos, los enlaces y la orientación de implementación se basan **únicamente** en la [ArchWiki](https://wiki.archlinux.org/) pública — la wiki oficial de Arch Linux. Donde entren repositorios de usuarios, aplica lo mismo (p. ej. [Arch User Repository](https://wiki.archlinux.org/title/Arch_User_Repository), [AUR helpers](https://wiki.archlinux.org/title/AUR_helpers)), no blogs ni guías no oficiales. La wiki sigue siendo la fuente autoritativa y actual; `archforge` es una utilidad y puede ir detrás de los cambios en la wiki.

&nbsp;

## 🚀 Inicio rápido

```bash
git clone https://github.com/h3n-x/archforge.git
cd archforge
chmod +x archforge
./archforge
```

> [!TIP]
> Usa `./archforge --dry-run` primero para ver qué cambiaría sin aplicar nada.

&nbsp;

## 🖥️ Menú interactivo

> [!NOTE]
> Sin `--modules` o `--profile`, aparece un **menú numerado en dos columnas**. Puedes elegir por **número** (`1 3 5`), por **id de módulo** (`pacman firewall`), la palabra **`all`** para todos, o **`q`** para salir. Separa entradas con **espacios o comas**. Algunas filas muestran **⚠** cuando el módulo puede tocar hardware o conviene revisar antes de aplicar.

&nbsp;

## 🎯 Perfiles del sistema

En lugar de seleccionar módulos individuales manualmente, puedes aplicar una configuración prediseñada con `--profile=NOMBRE`:

```bash
./archforge --profile=desktop-full
```

| Perfil | Objetivo / Caso de uso | Módulos base de software |
|---|---|---|
| `server` | Servidores headless, VPS o Home Labs | `pacman`, `aur-helper`, `systemd`, `users-groups`, `network`, `dns`, `firewall`, `antivirus`, `locale`, `ssd`, `performance` |
| `desktop-minimal` | Base ligera de escritorio / TWM (Hyprland, Sway, i3) | `pacman`, `aur-helper`, `systemd`, `users-groups`, `network`, `dns`, `firewall`, `keyboard`, `locale`, `fonts`, `libinput`, `audio`, `ssd`, `performance` |
| `desktop-full` | Estación de trabajo diaria completa | `desktop-minimal` + `bluetooth`, `printing` |
| `gaming` | PCs optimizadas para juegos | `pacman`, `aur-helper`, `network`, `dns`, `firewall`, `keyboard`, `locale`, `fonts`, `libinput`, `audio`, `bluetooth`, `ssd`, `performance`, `steam` |

> [!NOTE]
> **Línea base de seguridad universal**: Todos los perfiles incluyen `dns` (con DNSSEC / DoT) y `firewall` (`nftables`).
>
> **Resolución automática de hardware**: Por defecto, `archforge` escanea dinámicamente el bus del equipo:
> - **Escaneo multi-GPU en el bus PCI**: Escanea los controladores PCI (`lspci`), configurando arquitecturas híbridas (p. ej. APU AMD integrada + GPU NVIDIA discreta en portátiles) sin colisiones de drivers.
> - **Portátiles**: Inspecciona la presencia real de baterías (`/sys/class/power_supply`) para aplicar `tlp` y `acpid` únicamente en dispositivos móviles reales.
> - **Sensores**: Inspecciona la virtualización con `systemd-detect-virt`, inyectando `sensors` en hardware físico y omitiéndolo limpiamente dentro de máquinas virtuales.
>
> Usa `--no-hardware-detect` si deseas estrictamente la base de software sin detección automática de controladores de hardware.

&nbsp;

## 📦 Instalación (sistema)

```bash
sudo make install
```

Instala el script `archforge` y copia `lib/` y `modules/` bajo `$(PREFIX)/share/archforge` (prefijo por defecto: `/usr/local`). Consulta el `Makefile` para `DESTDIR` y `PREFIX`.

&nbsp;

## 🎨 Vista previa

<p align="center">
  <img src="assets/archforge.png" alt="archforge — menú de módulos numerados, banner y recuadro Select modules en la terminal" width="920"/>
  <br/><br/>
  <sub><i>TUI interactiva: ejecuta <code>./archforge</code> en una terminal UTF-8 para verla en vivo.</i></sub>
</p>

&nbsp;

## 📋 Módulos disponibles

| ID | Nombre | Categoría | Descripción |
|---|---|---|---|
| `pacman` | Package Management: pacman | Gestión de paquetes | [Configurar pacman.conf, multilib, reflector, keyring, pkgfile, paccache](https://wiki.archlinux.org/title/Pacman) |
| `aur-helper` | Package Management: AUR helper | Gestión de paquetes | [Detectar/instalar AUR helper (yay/paru), optimización de makepkg](https://wiki.archlinux.org/title/AUR_helpers) |
| `systemd` | System Services: systemd | Servicios del sistema | [Journal persistente (drop-in), análisis de arranque, timesyncd](https://wiki.archlinux.org/title/Systemd) |
| `users-groups` | System: Users and Groups | Servicios del sistema | [Cuentas de usuario, grupos, configuración sudo](https://wiki.archlinux.org/title/Users_and_groups) |
| `dns` | Security: DNS configuration | Seguridad | [Detección de proveedor DNS, 6 proveedores, DNSSEC, DoT](https://wiki.archlinux.org/title/Domain_name_resolution) |
| `firewall` | Security: Firewall (nftables) | Seguridad | [Perfiles nftables (desktop/server/strict), rate limiting SSH, log de drops](https://wiki.archlinux.org/title/Nftables) |
| `antivirus` | Security: Antivirus (ClamAV) | Seguridad | [ClamAV con config de clamd, freshclam, escaneo en tiempo real opcional + timer](https://wiki.archlinux.org/title/ClamAV) |
| `network` | Networking: network configuration | Red | [Hostname, /etc/hosts, NetworkManager, ahorro WiFi, dominio regulatorio, MAC aleatoria](https://wiki.archlinux.org/title/NetworkManager) |
| `tlp` | Power: TLP | Gestión de energía | [Optimización de batería, umbrales de carga, lista de exclusión USB](https://wiki.archlinux.org/title/TLP) |
| `acpid` | Power: ACPI events (acpid) | Gestión de energía | [Suspensión al cerrar tapa, eventos de botón de encendido](https://wiki.archlinux.org/title/Acpid) |
| `ssd` | Optimization: SSD | Optimización | [Verificar TRIM, fstrim timer, discard continuo, noatime, tmpfs /tmp](https://wiki.archlinux.org/title/Solid_state_drive) |
| `performance` | Optimization: Performance | Optimización | [Sysctls de red, THP, zram, OOM killer, gobernador de CPU](https://wiki.archlinux.org/title/Improving_performance) |
| `sensors` | Optimization: Hardware sensors | Optimización | [lm_sensors, detección de sensores](https://wiki.archlinux.org/title/Lm_sensors) |
| `libinput` | Input: libinput (touchpad/mouse) | Entrada | [Touchpad, scroll natural, TrackPoint, nota Wayland](https://wiki.archlinux.org/title/Libinput) |
| `keyboard` | Input: Keyboard layout | Entrada | [Keymap de consola, layout X11 vía localectl](https://wiki.archlinux.org/title/Keyboard_configuration_in_console) |
| `fonts` | Console: Fonts | Consola | [terminus-font, noto-fonts, ttf-liberation, vconsole.conf](https://wiki.archlinux.org/title/Fonts) |
| `locale` | Console: Locale & timezone | Consola | [locale-gen, zona horaria, sincronización de reloj hardware, NTP](https://wiki.archlinux.org/title/Locale) |
| `amd` | Graphics: AMD GPU (AMDGPU) | Gráficos | [Mesa, RADV Vulkan, KMS temprano, multilib 32-bit opcional](https://wiki.archlinux.org/title/AMDGPU) |
| `intel` | Graphics: Intel Graphics | Gráficos | [Mesa, ANV Vulkan, aceleración VA-API, multilib 32-bit opcional](https://wiki.archlinux.org/title/Intel_graphics) |
| `nouveau` | Graphics: Nouveau (open-source NVIDIA) | Gráficos | [Driver NVIDIA de código abierto](https://wiki.archlinux.org/title/Nouveau) |
| `nvidia` | Graphics: NVIDIA driver | Gráficos | [Instalación del driver propietario de NVIDIA](https://wiki.archlinux.org/title/NVIDIA) |
| `steam` | Gaming: Steam | Gaming | [Steam, deps Proton/Wine, fd-limit, GameMode, MangoHud](https://wiki.archlinux.org/title/Steam) |
| `audio` | Peripherals: Audio (PipeWire & WirePlumber) | Periféricos | [PipeWire, WirePlumber, emulación PulseAudio](https://wiki.archlinux.org/title/PipeWire) |
| `bluetooth` | Peripherals: Bluetooth (BlueZ) | Periféricos | [BlueZ, bluetoothctl, GUI blueman](https://wiki.archlinux.org/title/Bluetooth) |
| `printing` | Peripherals: Printing (CUPS) | Periféricos | [CUPS, drivers de impresora, avahi](https://wiki.archlinux.org/title/CUPS) |
| `vmware-host` | Virtualization: VMware Workstation (host) | Virtualización | [Configuración de host VMware Workstation](https://wiki.archlinux.org/title/VMware) |

&nbsp;

## ⚙️ Opciones (CLI)

```
--modules m1,m2,...    Ejecutar módulos específicos (omite menú)
--dry-run              Mostrar qué cambiaría, sin ejecutar nada
--yes, -y              Omitir todas las confirmaciones
--aur-helper=NAME      Forzar AUR helper (yay, paru, ...)
--help, -h             Mostrar ayuda
--version              Mostrar versión
```

&nbsp;

## 🔄 Restaurar

```bash
./archforge restore
```

Muestra sesiones anteriores y permite restaurar archivos respaldados de forma selectiva.

&nbsp;

## 🛠️ Desarrollo

```bash
make lint    # shellcheck
make test    # bats
make check   # lint + pruebas
```

&nbsp;

## 📎 Requisitos

- **Arch Linux** (o derivado compatible)
- **bash** >= 5.0
- Permisos **sudo**

&nbsp;

## 📚 Documentación

| Recurso | Descripción |
|---|---|
| [docs/es/modules.md](docs/es/modules.md) | Lista de módulos con paquetes y enlaces wiki (español) |
| [docs/en/modules.md](docs/en/modules.md) | Lo mismo en inglés |
| [README.md](README.md) | Este readme en inglés |

&nbsp;

## 🤝 Contribuir

Las contribuciones son bienvenidas. Ver [CONTRIBUTING.md](CONTRIBUTING.md) para pruebas, `shellcheck` y la API de módulos (`module_info` / `module_run`).

&nbsp;

## 🙋 Preguntas frecuentes

- **P: _¿Cómo evito el menú?_** \
  **R:** Pasa los ids explícitos: `./archforge --modules pacman,firewall` (separados por comas), o usa un perfil prediseñado: `./archforge --profile=desktop-full`. Para ejecutar todo sin escribir cada id, usa el menú interactivo y escribe **`all`**.

- **P: _¿Puedo combinar un perfil con módulos adicionales?_** \
  **R:** Sí. Pasa `--profile=NOMBRE --modules mod1,mod2`. Los módulos se combinan y se ordenan automáticamente según el orden de ejecución seguro sin duplicados.

- **P: _¿Dónde se guardan los respaldos?_** \
  **R:** Por defecto en `~/.local/share/archforge/backups/<id-de-sesión>/`. Puedes cambiar la base con la variable de entorno `BACKUP_BASE_DIR`. Usa `./archforge restore` para elegir una sesión anterior de forma interactiva.

&nbsp;

## 💝 Agradecimientos

- [Arch Linux](https://archlinux.org/) y autores de [ArchWiki](https://wiki.archlinux.org/)
- Estructura del README inspirada en las plantillas de los ports de [Catppuccin](https://github.com/catppuccin/catppuccin) (badges, espaciado, secciones). **Sin afiliación** — solo inspiración de maquetación.

&nbsp;

<p align="center">
  <img src="https://raw.githubusercontent.com/catppuccin/catppuccin/main/assets/footers/gray0_ctp_on_line.svg?sanitize=true" alt=""/>
</p>

<p align="center">
  Copyright © 2026 <a href="https://github.com/h3n-x">h3n-x</a>
</p>

<p align="center">
  <a href="https://github.com/h3n-x/archforge/blob/main/LICENSE"><img src="https://img.shields.io/static/v1?style=for-the-badge&message=MIT&logoColor=d9e0ee&label=Licencia&labelColor=363a4f&color=a6e3a1" alt="Licencia MIT"/></a>
</p>
