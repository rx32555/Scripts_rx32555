# Rename-AnimeJellyfin

Script de PowerShell para renombrar archivos de anime al formato `SxxExx` compatible con **Jellyfin**, sin alterar el resto del nombre del archivo.

Diseñado para integrarse con el menú contextual **"Enviar a"** de Windows, con soporte para selección múltiple de carpetas y opción de deshacer cambios.

---

## El problema

Jellyfin identifica episodios buscando el patrón `SxxExx` en el nombre del archivo. Sin ese patrón, agrupa los episodios en **"Temporada desconocida"** y no los asocia correctamente a la serie.

```
ANTES  →  [Erai-raws] Tensei Kizoku - 01 [1080p][HEVC][5FD38D43].mkv
DESPUÉS →  [Erai-raws] Tensei Kizoku - S01E01 [1080p][HEVC][5FD38D43].mkv
```

Solo se modifica el número de episodio. El grupo fansub, calidad, hash y cualquier otro tag quedan intactos.

---

## Patrones soportados

| Patrón | Ejemplo antes | Ejemplo después |
|--------|--------------|-----------------|
| Guion + número (espacios) | `Show - 05 [1080p]` | `Show - S01E05 [1080p]` |
| Guion + número (underscores) | `[Group]_Show_-_05_[1080p]` | `[Group]_Show_-_S01E05_[1080p]` |
| Número sin guion | `Darker Than Black 01 [720p]` | `Darker Than Black S01E01 [720p]` |
| Estilo PuyaSubs/Gintama | `Gintama S3 - 28 [480p]` | `Gintama S03E28 [480p]` |
| Espaciado incorrecto | `Show - S01E01texto` | `Show - S01E01 texto` |

El número de temporada se detecta automáticamente desde la subcarpeta `Season N` de la ruta. Si no existe esa subcarpeta, se asume `S01`.

---

## Instalación

### Archivos

| Archivo | Descripción |
|---------|-------------|
| `Rename-AnimeJellyfin.ps1` | Script principal |
| `Rename-AnimeJellyfin.bat` | Lanzador para el menú "Enviar a" |

### Paso 1 — Copiar los archivos

Copia ambos archivos a una carpeta fija en tu equipo, por ejemplo:

```
C:\Rename-AnimeJellyfin.ps1
C:\Rename-AnimeJellyfin.bat
```

> Los dos archivos deben estar en la misma carpeta. Si los mueves, edita la variable `PS1_PATH` del `.bat`.

### Paso 2 — Agregar al menú "Enviar a"

1. Abre la carpeta SendTo pegando esta ruta en el Explorador:
   ```
   shell:sendto
   ```
2. Crea un **acceso directo** al `.bat` dentro de esa carpeta.
3. Renómbralo como quieras que aparezca en el menú, ej: `Rename Jellyfin`.

### Paso 3 — Política de ejecución de PowerShell (solo una vez)

Si PowerShell bloquea la ejecución de scripts en tu equipo, ejecuta esto una única vez:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

El `.bat` ya incluye `-ExecutionPolicy Bypass` internamente, por lo que habitualmente no es necesario.

---

## Uso

### Desde el menú "Enviar a" (uso normal)

1. Selecciona una o varias carpetas de anime en el Explorador.
2. Clic derecho → **Enviar a → Rename Jellyfin**.
3. Se abre una ventana de consola, renombra y muestra el resultado.
4. Presiona Enter para cerrar.

### Desde PowerShell (una carpeta)

```powershell
.\Rename-AnimeJellyfin.ps1 -Path "J:\ANIME\Trinity Seven"
```

### Desde PowerShell (varias carpetas)

```powershell
.\Rename-AnimeJellyfin.ps1 -Path "J:\ANIME\Trinity Seven","J:\ANIME\Bleach"
```

### Desde CMD o cualquier consola (vía .bat)

```cmd
Rename-AnimeJellyfin.bat "J:\ANIME\Full Metal Panic! Invisible Victory"
```

---

## Deshacer cambios

Cada carpeta procesada genera un archivo `_rename_undo.json` con el registro de todos los cambios realizados.

Para restaurar los nombres originales, selecciona la carpeta y vuelve a ejecutar el script. Detectará el backup automáticamente y preguntará:

```
+----------------------------------------------+
|   BACKUPS DETECTADOS                         |
+----------------------------------------------+
  Carpetas con backup : 1
  Cambios totales     : 12
    * J:\ANIME\Trinity Seven

  ¿Restaurar nombres originales? [S/N]
```

- **S** → revierte todos los cambios y elimina el `_rename_undo.json`.
- **N** → ignora el backup y procede con un nuevo renombrado.

Si la restauración falla parcialmente, el `.json` se conserva para reintentar.

---

## Estructura esperada de carpetas

El script funciona con cualquier estructura, pero detecta mejor la temporada si las carpetas siguen esta jerarquía:

```
J:\ANIME\
  └─ Trinity Seven\
       ├─ Season 1\
       │    ├─ [Hoshizora]_Trinity_Seven_-_01_[BD][1080p].mkv
       │    └─ [Hoshizora]_Trinity_Seven_-_02_[BD][1080p].mkv
       └─ Season 2\
            └─ ...
```

Si no hay subcarpeta `Season N`, todos los episodios se renombran como `S01`.

---

## Configuración del .bat

Si cambias la ubicación de los archivos, edita la variable al inicio del `.bat`:

```bat
set "PS1_PATH=C:\Rename-AnimeJellyfin.ps1"
```

---

## Limitaciones conocidas

- Episodios con **número absoluto sin corchetes** (ej: `Naruto Shippuuden 180`) no se renombran automáticamente — el patrón es ambiguo para el parser.
- Si una serie tiene un número en el propio título (ej: `86 - EIGHTY SIX`), puede haber falsos positivos. Revisar con dry-run manual antes de procesar.
- El script no crea ni modifica carpetas `Season N`, solo lee el nombre de la subcarpeta existente para determinar el número de temporada.

---

## Compatibilidad

- Windows 10 / 11
- Windows PowerShell 5.1 (incluido en Windows, sin instalación adicional)
- PowerShell 7+ también compatible
