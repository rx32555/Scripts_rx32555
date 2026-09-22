# Actualización Forzada y Cierre de Instancias

## Estado del código

- [x] Al necesitar una recopia, el setup cierra los procesos que se ejecutan desde la carpeta portable y espera hasta dos segundos.
- [x] Si queda algún proceso activo, muestra el error en consola o en el log de la GUI y termina sin reemplazar la copia.
- [x] El lanzador delega la actualización al setup y muestra el error si este falla.
- [x] Pruebas de cierre, bloqueo, `-WhatIf` y salida de la GUI.
- [ ] Actualización de la copia instalada en `C:\ClaudePortable`: requiere ejecutar el setup en una sesión de Windows que permita consultar el paquete MSIX. En este entorno `Get-AppxPackage` devuelve `Operation is not supported on this platform (0x80131539)`.

## 1. Contexto y Diagnóstico Actual
- **Tipo de Instalación detectada**: MSIX (Microsoft Store).
- **Versión instalada en el sistema**: `2.2553.13.0` (en `C:\Program Files\WindowsApps\Claude_2.2553.13.0_x64__pzs8sxrjxfjjc`).
- **Versión en copia portable**: `2.110.0.0` (en `C:\ClaudePortable` con stamp del 15 de septiembre).
- **Causa del bloqueo**: 
  - Al ejecutar "Ejecutar / Actualizar Instancias", el script detecta que Claude se actualizó (`2.110.0.0 -> 2.2553.13.0`), pero omite la recopia porque detecta procesos activos de Claude corriendo desde `C:\ClaudePortable`.
  - El comportamiento actual en `Invoke-MultiSetup` y en el launcher es abortar/omitir la copia silenciosamente y seguir usando la versión vieja.

---

## 2. Requerimiento original (implementado en el repositorio)
Implementar el **cierre forzado de instancias** de Claude cuando se requiere actualizar la copia portable, notificando si no fue posible cerrarlas:

1. **Cierre forzado de procesos de Claude**:
   - En `Invoke-MultiSetup` (cuando `needsCopy` es verdadero y se detectan procesos en `TargetPortableDir`):
     - Intentar terminar los procesos correspondientes (ej. `Stop-Process -Force` o `taskkill.exe /F /PID ...`).
     - Esperar brevemente (ej. 1-2 segundos) a que los descriptores de archivo se liberen.
   - Si tras el intento siguen procesos activos:
     - Mostrar advertencia clara (en consola y/o ventana emergente `MessageBox` si está en modo GUI).
     - Informar que no se pudo cerrar la instancia y que no se puede reemplazar la copia portable.

2. **Visibilidad en la GUI**:
   - Asegurar que los mensajes de progreso y advertencias generados por el proceso hijo se muestren correctamente en la caja de log de la interfaz gráfica (revisar captura de flujos en `Start-GuiSetupJob`).

3. **Lanzador (`Launch-ClaudeProfile.ps1`)**:
   - Evaluar si el lanzador en segundo plano debe sugerir/ejecutar el cierre forzado o delegar la actualización a la ejecución manual / GUI.

---

## 3. Estado de Cambios Ya Realizados
- [x] Fix Bug 1: Detección de versión en modo `Direct` (Squirrel) añadida a `Launch-ClaudeProfile.ps1`.
- [x] Fix Bug 2: `Get-InstalledVersion` ahora escanea carpetas `app-*` más recientes para no leer rutas obsoletas.
- [x] Validación: Tests existentes (`Launcher.Tests.ps1`, `PortableCopy.Tests.ps1`, `RunLog.Tests.ps1`) pasando sin errores de sintaxis.
