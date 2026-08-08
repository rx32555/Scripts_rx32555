# Setup-ClaudeMulti

Script de PowerShell para correr **dos o más instancias de Claude Desktop en paralelo** en el mismo PC, cada una con su propia cuenta, sesión, historial local, MCPs y configuración.

Anthropic no ofrece cambio de cuenta nativo: hay que cerrar sesión y volver a entrar cada vez. Este script elimina ese paso.

---

## El problema

Claude Desktop guarda **todo** el estado del usuario —incluido el token de sesión— en una única carpeta *user data* (`%APPDATA%\Claude`). Como solo hay una, solo hay una cuenta activa a la vez.

```
ANTES    →  Cerrar sesión → login cuenta B → trabajar → cerrar sesión → login cuenta A...
DESPUÉS  →  Dos ventanas abiertas al mismo tiempo, una por cuenta.
```

Claude Desktop es una app Electron, y Electron acepta el parámetro `--user-data-dir`. Lanzando el ejecutable con una ruta distinta, esa ventana usa su propia carpeta y queda completamente aislada de la otra.

---

## Qué hace el script

| Paso | Detalle |
|------|---------|
| 1. Detectar | Busca la instalación de Claude Desktop (installer `.exe` o paquete MSIX) y su versión |
| 2. Copia portable | Solo si la instalación es MSIX: copia la app a `C:\ClaudePortable`, **o la actualiza si Claude cambió de versión** |
| 3. Accesos directos | Crea un `.lnk` por perfil en el Escritorio, cada uno con su `--user-data-dir` |

El **primer perfil** apunta a la carpeta por defecto (`%APPDATA%\Claude`), así conservas la sesión y los MCPs que ya tienes. Los siguientes usan `%APPDATA%\Claude-<Nombre>` y arrancan limpios.

En instalaciones MSIX el acceso directo del primer perfil **no** apunta a la copia portable, sino al paquete de la Store (`shell:AppsFolder\<AUMID>`). Así tu perfil principal conserva las actualizaciones automáticas; la copia portable solo la usan los perfiles extra.

---

## Actualizaciones

**Vuelve a hacer doble clic en `Setup-ClaudeMulti.bat` cuando quieras.** No hay nada más que hacer.

Al copiar la app, el script deja un sello `C:\ClaudePortable\.claude-multi.json` con la versión copiada. En cada ejecución compara ese sello con la versión instalada:

| Situación | Qué hace |
|-----------|----------|
| Misma versión | Nada. Termina en ~1 segundo. |
| Claude se actualizó | Rehace la copia portable sola y avisa `1.26000 -> 1.26832`. |
| Copia borrada, movida o corrupta | La rehace. |
| Hay Claude abierto desde la copia portable | No toca nada y te pide cerrar esas ventanas. |

El primer perfil no depende de esto: se lanza por el paquete de la Store y Windows lo actualiza solo.

`-Force` sigue existiendo para forzar la recopia aunque las versiones coincidan.

---

## Los dos escenarios de instalación

| Instalación | Ruta típica | Copia portable | ¿Admin? |
|-------------|-------------|----------------|---------|
| Installer `.exe` | `%LOCALAPPDATA%\AnthropicClaude` | No hace falta | No |
| MSIX / Microsoft Store | `C:\Program Files\WindowsApps` | Sí, a `C:\ClaudePortable` | Sí |

Windows bloquea ejecutar un `.exe` desde `WindowsApps` pasándole parámetros. Por eso en el segundo caso se necesita la copia previa.

---

## Instalación

### Archivos

| Archivo | Descripción |
|---------|-------------|
| `Setup-ClaudeMulti.ps1` | Script principal |
| `Setup-ClaudeMulti.bat` | Lanzador (evita tocar la política de ejecución de PowerShell) |

Ambos deben quedar **en la misma carpeta**.

### Uso

1. Doble clic en `Setup-ClaudeMulti.bat`.
2. Si el script avisa que necesita Administrador (caso Microsoft Store), ciérralo y ábrelo con botón derecho → **Ejecutar como administrador**.
3. En el Escritorio aparecen:
   - `Claude - Cuenta1 (perfil actual)` → tu sesión de siempre, intacta.
   - `Claude - Cuenta2` → pedirá login. Entra con la segunda cuenta.
4. Ambas ventanas pueden estar abiertas simultáneamente.

---

## Parámetros

| Parámetro | Por defecto | Descripción |
|-----------|-------------|-------------|
| `-Profiles` | `'Cuenta1','Cuenta2'` | Nombres de los perfiles. Acepta más de dos. Se validan (sin caracteres inválidos ni duplicados). |
| `-PortableDir` | `C:\ClaudePortable` | Destino de la copia portable (solo MSIX). |
| `-CopyMcpConfig` | — | Copia el nodo `mcpServers` de tu `claude_desktop_config.json` a cada perfil nuevo. Solo esa clave: no arrastra sesión, credenciales ni preferencias ligadas a tu cuenta. |
| `-Revert` | — | Deshace todo: accesos directos, carpetas de los perfiles extra y copia portable. |
| `-GrantWindowsAppsRead` | — | Autoriza sin preguntar el `takeown`+`icacls` sobre `WindowsApps`. Solo para ejecución desatendida. |
| `-Force` | — | Fuerza la recopia aunque la versión coincida, sobrescribe la config MCP ya copiada y, con `-Revert`, borra sin preguntar. |

Además soporta `-WhatIf` y `-Confirm`: `-WhatIf` muestra exactamente qué se crearía o borraría sin tocar nada.

```powershell
# Nombres personalizados, heredando tus MCPs en el perfil nuevo
powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1 -Profiles 'Personal','Trabajo' -CopyMcpConfig

# Tres perfiles
powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1 -Profiles 'Personal','Trabajo','Cliente'

# Ver qué haría, sin hacerlo
powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1 -Profiles 'Personal','Trabajo' -WhatIf

# Refrescar la copia portable tras una actualización de Claude
powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1 -Force
```

---

## Advertencias

- **Cowork corre en una VM Hyper-V única por máquina.** Solo una instancia puede usar Cowork a la vez. El chat normal sí funciona en ambas en paralelo.
- **Los MCPs no se heredan.** `claude_desktop_config.json` vive *dentro* de la carpeta de datos, así que cada perfil nuevo arranca con cero MCP servers. Usa `-CopyMcpConfig` para sembrarlos, o vuelve a configurarlos a mano. Ese archivo mezcla los MCP servers con preferencias de UI ligadas a la cuenta, por eso el script copia **solo** la clave `mcpServers`.
- **La copia portable no se actualiza sola en segundo plano.** Se actualiza al ejecutar `Setup-ClaudeMulti.bat`, que detecta la versión nueva por su cuenta (ver *Actualizaciones*). Si pasas semanas sin ejecutarlo, tus perfiles extra corren la versión vieja.
- **La copia portable pierde la identidad de paquete MSIX.** En las instancias extra pueden no funcionar los deep links `claude://`, las notificaciones nativas y el auto-update. El chat, los proyectos y los MCPs sí.
- **Permisos de `WindowsApps`.** En muchos equipos la carpeta ya es legible y no hace falta admin: el script **intenta la copia primero** y solo si falla ofrece dar lectura al grupo Administradores mediante `takeown` + `icacls`, pidiendo confirmación explícita. Es una carpeta protegida del sistema y en casos raros puede afectar las actualizaciones automáticas del paquete. Responder `N` cancela sin tocar nada.
- Esta es una solución de usuario, no algo soportado oficialmente por Anthropic.

---

## Alternativa sin modificar el sistema

Crear un **segundo usuario de Windows** y usar *Ejecutar como otro usuario* (Shift + botón derecho sobre el acceso directo). Aislamiento total, cero cambios en permisos. La contra: es más incómodo para el día a día.

---

## Revertir

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1 -Profiles 'Personal','Trabajo' -Revert
```

Usa los **mismos** `-Profiles` (y `-PortableDir`, si lo cambiaste) que al instalar. Borra los accesos directos, las carpetas `%APPDATA%\Claude-<Perfil>` de los perfiles extra y la copia portable. Pide confirmación antes de borrar datos de perfiles; añade `-Force` para saltarla o `-WhatIf` para solo ver la lista.

El perfil original en `%APPDATA%\Claude` nunca se toca.

---

## Requisitos

- Windows 10 / 11
- **Windows PowerShell 5.1** (el `powershell.exe` que trae Windows). PowerShell 7 no incluye `Get-AppxPackage`, así que no detecta las instalaciones de Microsoft Store; el script lo avisa y te dice cómo relanzarlo. El `.bat` ya usa el intérprete correcto.
- Claude Desktop instalado
