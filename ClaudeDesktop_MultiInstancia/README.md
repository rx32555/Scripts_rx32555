# Setup-ClaudeMulti

Script de PowerShell para correr **tres o más instancias de Claude Desktop en paralelo** en el mismo PC, cada una con su propia cuenta, sesión, historial local, MCPs y configuración.

Anthropic no ofrece cambio de cuenta nativo: hay que cerrar sesión y volver a entrar cada vez. Este script elimina ese paso.

---

## El problema

Claude Desktop guarda **todo** el estado del usuario —incluido el token de sesión— en una única carpeta *user data* (`%APPDATA%\Claude`). Como solo hay una, solo hay una cuenta activa a la vez.

```
ANTES    →  Cerrar sesión → login cuenta B → trabajar → cerrar sesión → login cuenta A...
DESPUÉS  →  Tres ventanas abiertas al mismo tiempo, una por cuenta.
```

Claude Desktop es una app Electron, y Electron acepta el parámetro `--user-data-dir`. Lanzando el ejecutable con una ruta distinta, esa ventana usa su propia carpeta y queda completamente aislada de la otra.

---

## Qué hace el script

| Paso | Detalle |
|------|---------|
| 1. Detectar | Busca la instalación de Claude Desktop (installer `.exe` o paquete MSIX) y su versión |
| 2. Copia portable | Solo si la instalación es MSIX: copia la app a `C:\ClaudePortable`, **o la actualiza si Claude cambió de versión** |
| 3. Iconos | Genera un `.ico` por perfil: el icono de Claude con una insignia de color y la inicial |
| 4. Lanzador | Instala en `%APPDATA%\ClaudeMulti` un lanzador que comprueba la versión antes de abrir |
| 5. Accesos directos | Crea un `.lnk` por perfil en el Escritorio, cada uno con su `--user-data-dir` |

El **primer perfil** apunta a la carpeta por defecto (`%APPDATA%\Claude`), así conservas la sesión y los MCPs que ya tienes. Los siguientes usan `%APPDATA%\Claude-<Nombre>` y arrancan limpios.

En instalaciones MSIX el acceso directo del primer perfil **no** apunta a la copia portable, sino al paquete de la Store (`shell:AppsFolder\<AUMID>`). Así tu perfil principal conserva las actualizaciones automáticas; la copia portable solo la usan los perfiles extra.

---

## Iconos de color

Cada perfil recibe su propio `.ico` en `%APPDATA%\ClaudeMulti\icons\`: el icono real de Claude con una insignia circular de color y la inicial del perfil. Los colores se asignan por orden y **nunca son naranjas** — el icono de Claude ya es coral y la insignia se volvería invisible.

| Orden | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| Color | azul | verde | morado | cian | rosa | azabache | oliva |

Los `.ico` son multi-resolución (256, 128, 64, 48, 32, 16 px), así que se distinguen igual en vista de iconos grandes que en lista.

> **Limitación honesta:** el color solo afecta al acceso directo. Una vez abierta la ventana, el icono de la barra de tareas lo pone la propia app, y no se puede cambiar sin modificar el ejecutable.

---

## Actualizaciones

Hay **dos** momentos en que se comprueba si Claude tiene versión nueva:

1. **Al abrir cualquier perfil.** El acceso directo no apunta al `.exe`: apunta a un lanzador que primero compara versiones. Si Claude se actualizó, refresca la copia portable (mostrando una ventana con el progreso) y luego abre Claude. Si está al día, abre directo sin retraso perceptible.
2. **Al ejecutar `Setup-ClaudeMulti.bat`**, como siempre.

En ambos casos no hay nada que recordar hacer.

Al copiar la app, el script deja un sello `C:\ClaudePortable\.claude-multi.json` con la versión copiada. En cada ejecución compara ese sello con la versión instalada:

| Situación | Qué hace |
|-----------|----------|
| Misma versión | Nada. Termina en ~1 segundo. |
| Claude se actualizó | Rehace la copia portable sola y avisa `1.26000 -> 1.26832`. |
| Copia borrada, movida o corrupta | La rehace. |
| Hay Claude abierto desde la copia portable | No toca nada y abre igual (no se puede reemplazar un `.exe` en uso). |

El primer perfil no depende de esto: se lanza por el paquete de la Store y Windows lo actualiza solo.

`-Force` sigue existiendo para forzar la recopia aunque las versiones coincidan.

### Qué se instala en `%APPDATA%\ClaudeMulti`

| Archivo | Para qué |
|---------|----------|
| `launch.vbs` | Arranca el lanzador oculto, sin parpadeo de consola negra |
| `Launch-ClaudeProfile.ps1` | Compara versiones, actualiza si toca y abre el perfil |
| `Setup-ClaudeMulti.ps1` | Copia del script, para que el lanzador pueda actualizar aunque muevas el repositorio |
| `config.json` | Perfiles, rutas y modo de instalación |
| `icons\*.ico` | Un icono por perfil |

Con `-NoLauncher` los accesos directos apuntan al `.exe` directamente (comportamiento clásico, sin comprobación al abrir). Los iconos de color se siguen aplicando.

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
2. Se abrirá la **Interfaz Gráfica de Usuario (GUI nativa)** con un panel de escritorio:
   - **Lista de Perfiles Activos**: Muestra cada cuenta con sus notas o correos asignados.
   - **Botonera de Acciones**:
     - ▶ **Ejecutar / Actualizar Instancias**: Configura e instala las instancias.
     - **+ Anadir Perfil**: Crea una nueva cuenta personalizada (`Trabajo`, `Cuenta4`, etc.) manteniendo intactas las existentes.
     - **Editar Nota/Email**: Asigna una dirección o nota (ej. `trabajo@empresa.com`) a cualquier perfil.
     - **Memoria compartida** (casilla): activa los MCP servers comunes a todas las cuentas.
     - **Health Check**: Diagnóstico completo de ejecutables, accesos directos y espacio en disco.
     - **Limpiar Cache**: Elimina archivos temporales liberando MB/GB en disco.
     - **Crear / Restaurar Backup**: Genera o restaura respaldos comprimidos `.zip`.
     - **Eliminar Perfil**: Borra el perfil seleccionado en la lista y deja el resto intacto.
     - **Revertir**: Elimina perfiles secundarios.
   - **Consola de Salida Integrada**: Muestra el progreso de cada acción en vivo dentro de la misma ventana.
3. Si prefieres la consola de texto en terminal, puedes ejecutar el script con el parámetro `-CLI`.

---

## Parámetros

| Parámetro | Por defecto | Descripción |
|-----------|-------------|-------------|
| `-Profiles` | `'Cuenta1','Cuenta2','Cuenta3'` | Nombres de los perfiles. Acepta tres o más. |
| `-GUI` | — | Abre la Interfaz Gráfica de Usuario nativa en Windows Forms. |
| `-CLI` | — | Fuerza el modo consola de texto interactivo en terminal. |
| `-Language` | Auto (según Windows) | Idioma de toda la interfaz: ventana, menú de texto y mensajes de progreso (`es` / `en`). |
| `-PortableDir` | `C:\ClaudePortable` | Destino de la copia portable (solo MSIX). |
| `-CopyMcpConfig` | — | Copia el nodo `mcpServers` de tu `claude_desktop_config.json` a cada perfil nuevo. Fusiona por clave: no pisa los MCP servers que ya tuviera ese perfil. |
| `-SharedMemory` | — | Siembra en **todos** los perfiles dos MCP servers apuntando a una carpeta común, para que las cuentas compartan contexto. Requiere Node.js. |
| `-SharedDir` | `%APPDATA%\ClaudeShared` | Carpeta de la memoria compartida. Queda fuera de `%APPDATA%\ClaudeMulti` a propósito: `-Revert` no la borra. |
| `-NoLauncher` | — | Los accesos directos apuntan al `.exe` directamente, sin comprobar versión al abrir. |
| `-RemoveProfile` | — | Elimina uno o varios perfiles concretos y deja el resto intacto. No admite el primero. |
| `-KeepData` | — | Con `-RemoveProfile`, conserva la carpeta de datos del perfil eliminado. |
| `-Revert` | — | Deshace todo: accesos directos, carpetas de los perfiles extra, `%APPDATA%\ClaudeMulti` y copia portable. |
| `-GrantWindowsAppsRead` | — | Autoriza sin preguntar el `takeown`+`icacls` sobre `WindowsApps`. Solo para ejecución desatendida. |
| `-Force` | — | Fuerza la recopia aunque la versión coincida, sobrescribe la config MCP ya copiada y, con `-Revert`, borra sin preguntar. |

Además soporta `-WhatIf` y `-Confirm`: `-WhatIf` muestra exactamente qué se crearía o borraría sin tocar nada.

```powershell
# Nombres personalizados, heredando tus MCPs en el perfil nuevo
powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1 -Profiles 'Personal','Trabajo' -CopyMcpConfig

# Tres perfiles
powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1 -Profiles 'Personal','Trabajo','Cliente'

# Las tres cuentas compartiendo la misma carpeta de contexto
powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1 -Profiles 'Personal','Trabajo','Cliente' -SharedMemory

# Ver qué haría, sin hacerlo
powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1 -Profiles 'Personal','Trabajo' -WhatIf

# Refrescar la copia portable tras una actualización de Claude
powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1 -Force
```

---

## Idioma

`-Language es` / `-Language en` cambian **todo** lo que se ve: los botones y diálogos de la ventana, el menú de texto y los ~130 mensajes de progreso que salen por consola (y que la ventana reproduce en su panel de log). Sin el parámetro, se elige por el idioma de Windows.

También cambia el nombre de los accesos directos:

```
es  ->  Claude - Cuenta1 (correo@x.com) (perfil actual).lnk
en  ->  Claude - Cuenta1 (correo@x.com) (current profile).lnk
```

El script reconoce los dos sufijos, así que si cambias de idioma reemplaza el acceso viejo en vez de dejar dos en el Escritorio.

El texto de la interfaz es ASCII puro a propósito (`configuracion`, no `configuración`): la consola de Windows no tiene un juego de caracteres fiable y los acentos salían como símbolos raros.

## Qué se comparte y qué no

`--user-data-dir` solo redirige la carpeta de Electron. Lo que vive **fuera** de ella es común a todas las instancias, se quiera o no.

| | Dónde vive | ¿Compartido? |
|---|---|---|
| Sesión, chats, proyectos | `%APPDATA%\Claude-<Perfil>` | No — por eso existe este script |
| Memoria del chat ("Claude recuerda") | Servidor, atada a la cuenta | No, y no hay forma local de hacerlo |
| MCP servers del Desktop | `claude_desktop_config.json`, dentro de la carpeta del perfil | No, salvo `-CopyMcpConfig` o `-SharedMemory` |
| Memoria de Claude Code, `CLAUDE.md`, skills, plugins | `%USERPROFILE%\.claude` | **Sí, siempre** |
| Credenciales de Claude Code | `%USERPROFILE%\.claude\.credentials.json` | **Sí, siempre** |

Esa última fila conviene tenerla presente: la sesión de Claude Code **no** sigue a la cuenta con la que abriste esa ventana de Desktop.

### `-SharedMemory`

La memoria del chat no se puede compartir, pero sí se le pueden dar a las tres cuentas los **mismos MCP servers apuntando a una carpeta común**. Con `-SharedMemory` el script siembra en cada perfil —incluido el primero— dos servidores:

| Servidor | Qué hace |
|---|---|
| `shared-memory` | Grafo de conocimiento sobre `<SharedDir>\memory.json`. Lo que una cuenta guarda, las otras lo leen. |
| `shared-files` | Acceso de lectura/escritura a `<SharedDir>`. Deja ahí un `.md` y las tres cuentas lo ven. |

La carpeta se crea con un `LEEME.md` que explica para qué es.

Detalles que importan:

- **Necesita Node.js en el `PATH`.** La config se escribe como `cmd.exe /c npx -y <paquete>`, que es la única forma que funciona en Windows: `npx` a secas da `ENOENT`, apuntar directo a `npx.cmd` da `EINVAL` desde el parche de CVE-2024-27980 (Node ya no lanza `.cmd` sin shell), y meter la ruta de `npx.cmd` entre comillas dentro de `cmd /c` se rompe si tiene espacios. Si no encuentra `npx`, el script avisa y sigue con el resto de la configuración sin tocar nada.
- **Fusiona, no reemplaza.** Si un perfil ya tenía MCP servers propios, se conservan. Y si `shared-memory` ya existe, no se sobrescribe salvo con `-Force`.
- **Hay que reiniciar Claude** para que la ventana recoja los servidores nuevos.
- **No hay bloqueo entre instancias.** Si dos ventanas escriben en `memory.json` a la vez, gana la última. Para uso normal —una cuenta anotando, las otras leyendo— no da problemas.
- **`-Revert` no borra `SharedDir`.** Vive fuera de `%APPDATA%\ClaudeMulti` justo para eso; si ya no la quieres, bórrala a mano.

## Advertencias

- **Cowork corre en una VM Hyper-V única por máquina.** Solo una instancia puede usar Cowork a la vez. El chat normal sí funciona en ambas en paralelo.
- **Los MCPs no se heredan.** `claude_desktop_config.json` vive *dentro* de la carpeta de datos, así que cada perfil nuevo arranca con cero MCP servers. Usa `-CopyMcpConfig` para sembrarlos, o vuelve a configurarlos a mano. Ese archivo mezcla los MCP servers con preferencias de UI ligadas a la cuenta, por eso el script copia **solo** la clave `mcpServers`.
- **La copia portable no se actualiza sola en segundo plano.** Se actualiza al ejecutar `Setup-ClaudeMulti.bat`, que detecta la versión nueva por su cuenta (ver *Actualizaciones*). Si pasas semanas sin ejecutarlo, tus perfiles extra corren la versión vieja.
- **La copia portable pierde la identidad de paquete MSIX.** En las instancias extra pueden no funcionar los deep links `claude://`, las notificaciones nativas y el auto-update. El chat, los proyectos y los MCPs sí.
- **Permisos de `WindowsApps`.** En muchos equipos la carpeta ya es legible y no hace falta admin: el script **intenta la copia primero** y solo si falla ofrece dar lectura al grupo Administradores mediante `takeown` + `icacls`, pidiendo confirmación explícita. Es una carpeta protegida del sistema y en casos raros puede afectar las actualizaciones automáticas del paquete. Responder `N` cancela sin tocar nada.
- **Cowork ocupa mucho disco.** La imagen de la VM (`vm_bundles`) puede pasar de 9 GB por perfil que la use. Queda fuera de los backups siempre, y *Limpiar Cache* solo la borra si lo confirmas — la app la vuelve a descargar entera la próxima vez.
- Esta es una solución de usuario, no algo soportado oficialmente por Anthropic.

---

## Alternativa sin modificar el sistema

Crear un **segundo usuario de Windows** y usar *Ejecutar como otro usuario* (Shift + botón derecho sobre el acceso directo). Aislamiento total, cero cambios en permisos. La contra: es más incómodo para el día a día.

---

## Eliminar un perfil suelto

`-Revert` es todo o nada. Para quitar una cuenta y conservar las demás:

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1 -RemoveProfile 'Cliente'
```

Borra su acceso directo, su carpeta `%APPDATA%\Claude-<Perfil>`, su icono y su entrada en `config.json`. El lanzador, la copia portable y los demás perfiles no se tocan. Pide confirmación antes de borrar datos; `-Force` la salta y `-WhatIf` solo enseña la lista.

En la interfaz es el botón **Eliminar Perfil**, que actúa sobre el perfil seleccionado en la lista; en el menú de texto, la opción `[11]`.

> **El primer perfil no se puede quitar por aquí.** Su carpeta de datos es `%APPDATA%\Claude` —tu sesión original, que `-Revert` tampoco borra nunca— y además *ser el primero de la lista* es justo lo que hace que un perfil use esa carpeta: si se fuera, el segundo pasaría a serlo y heredaría una sesión que no es la suya. Para desinstalar del todo está `-Revert`.

Con `-KeepData` lo saca de la lista pero conserva la carpeta de datos: queda como *huérfana* y el Health Check te la recuerda, por si algún día quieres readoptarla.

## Revertir

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1 -Profiles 'Personal','Trabajo','Cliente' -Revert
```

Usa los **mismos** `-Profiles` (y `-PortableDir`, si lo cambiaste) que al instalar. Borra los accesos directos, las carpetas `%APPDATA%\Claude-<Perfil>` de los perfiles extra, `%APPDATA%\ClaudeMulti` (lanzador e iconos) y la copia portable. Pide confirmación antes de borrar datos de perfiles; añade `-Force` para saltarla o `-WhatIf` para solo ver la lista.

El perfil original en `%APPDATA%\Claude` nunca se toca.

---

## Requisitos

- Windows 10 / 11
- **Windows PowerShell 5.1** (el `powershell.exe` que trae Windows). PowerShell 7 no incluye `Get-AppxPackage`, así que no detecta las instalaciones de Microsoft Store; el script lo avisa y te dice cómo relanzarlo. El `.bat` ya usa el intérprete correcto.
- Claude Desktop instalado
