# SmartMuxer

SmartMuxer es un script en Batch (`.bat`) diseñado para automatizar y facilitar la inyección de subtítulos, audios, fuentes y capítulos a archivos de video MKV utilizando `mkvmerge` (de la suite MKVToolNix).

## Características

- **Drag & Drop:** Funciona arrastrando y soltando archivos directamente sobre el `.bat`.
- **Detección Automática de Idiomas:** Si el archivo tiene un sufijo de idioma (por ejemplo, `.es.ass`, `.eng.srt`, `.jpn.mka`), el script detecta automáticamente el idioma.
- **Soporte para Pistas Forzadas (Forced/Signs):** Los subtítulos que incluyen las palabras `forced`, `signs` o `songs` se etiquetan automáticamente como pistas forzadas.
- **Manejo Masivo de Fuentes:** Adjunta automáticamente múltiples archivos de fuentes (`.ttf`, `.otf`, `.ttc`, `.woff`, `.woff2`) configurando sus MIME-types correctos de forma automática para asegurar la compatibilidad en reproductores (evitando problemas de carga de tipografías en ASS).
- **Auto-descarga de MKVToolNix:** Si no tienes instalado `mkvmerge.exe` o no se encuentra en la carpeta `dependencias`, el script intentará descargarlo automáticamente desde el sitio oficial en su versión portable.

### Novedades en v8.3
- **Modo Express Automático:** Al finalizar el escaneo de adjuntos, presiona `ENTER` para que el script aplique las mejores prácticas de una sola vez: añade todos los subtítulos y audios sin borrar los del MKV, añade todas las tipografías detectadas y reemplaza capítulos o videos si adjuntas nuevos.
- **Inteligencia en Pistas por Defecto (Audio y Subtítulo):** Detecta los idiomas tanto de las pistas nuevas que arrastras como de las pistas que ya tenía tu MKV. Automáticamente marca como pista por defecto (`--default-track`) siguiendo la estricta norma:
  - **Audios:** Japonés (`jpn`) > Latino (`lat`) > España (`spa`/`es`) > Inglés (`eng`).
  - **Subtítulos:** Latino (`lat`) > España (`spa`/`es`) > Inglés (`eng`).
- Interfaz dinámica re-diseñada con temporizadores de autoejecución para máxima rapidez al procesar lotes de capítulos.

## Uso

1. Arrastra sobre `SmartMuxer_v8.3.bat`:
   - 1 archivo `.mkv` base.
   - Todos los archivos adjuntos que quieras (`.ass`, `.mka`, `.ttf`, etc.).
2. Suelta el ratón.
3. El script los agrupará y mostrará un resumen. Presiona **ENTER** para el **Modo Express** (ideal para la mayoría de los escenarios) o **P** para configurar paso a paso.
4. Espera a que termine. El resultado se guardará como `<nombre_original>_muxed.mkv`.

## Dependencias

- **MKVToolNix:** Específicamente `mkvmerge.exe`.
  - El script lo buscará en su propia carpeta o en una subcarpeta llamada `dependencias`.
  - Si no existe, el propio script te ofrecerá descargar e instalar la dependencia portátil automáticamente.
- **PowerShell (nativo en Windows):** Utilizado temporalmente para leer teclas durante el countdown de confirmación sin necesidad de pulsar ENTER obligatoriamente en `choice`, y para la descarga segura desde web (TLS 1.2).
