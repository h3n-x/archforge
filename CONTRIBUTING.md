# Contribuir / Contributing

## Español

### Ejecutar pruebas
```bash
make test
```

### Linting
```bash
make lint
```

### Estructura de módulos
Cada módulo debe exponer dos funciones:

- `module_info` — imprime nombre, versión y descripción del módulo.
- `module_run` — lógica principal del módulo.

Códigos de salida:
- `0` — éxito
- `2` — uso incorrecto / argumentos inválidos
- Otro — error inesperado

### Ejecución segura de comandos (`run_cmd` vs `run_cmd_secret`)
- `run_cmd <cmd> [args...]` — Wrapper estándar de ejecución. En modo normal ejecuta el comando, muestra stdout/stderr en pantalla y registra la traza y salida completa en `LOG_FILE`. En `--dry-run` o `ARCHFORGE_TEST` intercepta la ejecución.
- `run_cmd_secret <label> <cmd> [args...]` — Úsalo obligatoriamente cuando un comando maneje **material sensible** (tokens de API, PINs de emparejamiento Bluetooth, claves o contraseñas). Ejecuta el comando directamente pero registra únicamente `[EXEC  ] [SECRET: <label>]` en `LOG_FILE`, evitando que contraseñas o argumentos sensibles queden persistidos en disco.
  ```bash
  # Ejemplo: comando que recibe un PIN o secreto por argumento
  run_cmd_secret "bluetooth-pin" bluetoothctl pair "${device_mac}" "${pin}"
  ```

### Documentación del repositorio
- `README.md` — inglés (vista por defecto en GitHub)
- `README.es.md` — español

Mantén ambos archivos alineados (misma estructura y contenido equivalente). No traduzcas nombres técnicos (`systemd`, `pacman`, flags, ids de módulos).

### Lista de verificación para Pull Requests
- [ ] `shellcheck` no reporta errores ni advertencias
- [ ] Las pruebas `bats` pasan (`make test`)
- [ ] Se agregó una entrada en `CHANGELOG.md`

---

## English

### Running tests
```bash
make test
```

### Linting
```bash
make lint
```

### Module structure
Every module must expose two functions:

- `module_info` — prints the module name, version, and description.
- `module_run` — main logic of the module.

Exit codes:
- `0` — success
- `2` — incorrect usage / invalid arguments
- Other — unexpected error

### Safe command execution (`run_cmd` vs `run_cmd_secret`)
- `run_cmd <cmd> [args...]` — Standard execution wrapper. Runs command in normal mode, teeing stdout/stderr to terminal and logging trace to `LOG_FILE`. In `--dry-run` or `ARCHFORGE_TEST`, intercepts execution.
- `run_cmd_secret <label> <cmd> [args...]` — Required whenever a command handles **sensitive material** (API tokens, Bluetooth pairing PINs, passwords, or keys). Executes the command directly while logging only `[EXEC  ] [SECRET: <label>]` to `LOG_FILE`, ensuring secret arguments and output are never persisted to disk.
  ```bash
  # Example: command receiving a PIN or sensitive argument
  run_cmd_secret "bluetooth-pin" bluetoothctl pair "${device_mac}" "${pin}"
  ```

### Repository documentation
- `README.md` — English (default on GitHub)
- `README.es.md` — Spanish

Keep both files in sync (same structure and equivalent content). Do not translate technical names (`systemd`, `pacman`, flags, module ids).

### Pull Request checklist
- [ ] `shellcheck` reports no errors or warnings
- [ ] `bats` tests pass (`make test`)
- [ ] An entry has been added to `CHANGELOG.md`

