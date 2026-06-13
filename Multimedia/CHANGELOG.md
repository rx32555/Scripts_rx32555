# Historial de Cambios (Changelog)

## v8.3
- **Mejora (Flujo):** Nuevo **Modo Express** como opción predeterminada. Presionando `ENTER` tras arrastrar los archivos, el script añade todo sin eliminar pistas previas y configura tipografías, video, etc., optimizando drásticamente los tiempos al muxear secuencias largas.
- **Mejora (Smart Audio):** Asignación inteligente de la pista de audio por defecto. Se escanean tanto los audios añadidos como los existentes en el MKV original para asignar el flag de predeterminado usando la jerarquía: Japonés > Latino > España > Inglés.
- **Mejora (UI):** Nueva integración de atajos de teclado (`ENTER`, `P`, `X`) sin requerir presionar Enter extra y con cuenta regresiva.
- **Fix (Line Endings):** Corregido fallo crítico de lectura de JSON en `mkvmerge` provocado por pérdida de sincronización del archivo Batch debido a saltos de línea UNIX (`\n`). Convertido el script forzosamente a CRLF (`\r\n`) para que `cmd.exe` parsee las subrutinas correctamente y no salte el parámetro `-o`.

## v8.2
- **Fix:** Resuelto límite estricto de Windows CMD (8191 caracteres) al arrastrar docenas de fuentes simultáneamente. Ahora se utiliza un archivo temporal (`@args.json`) para eludir cualquier restricción de longitud en los comandos de `mkvmerge`.
- **Mejora:** Asignación automática inteligente de la pista de subtítulo por defecto según el idioma. Prioriza `.lat` (Español Latino), luego `.es` (Español Castellano), y finalmente `.en` (Inglés).
- **Mejora:** Asignación explícita de `MIME-types` para formatos de fuentes como `.ttf`, `.otf`, `.ttc`, `.woff` y `.woff2`. Evita que `mkvmerge` adivine el formato como `application/octet-stream` e impida a reproductores cargar el estilo correctamente.
- **Mejora (UI):** Límite visual en la consola cuando se arrastran más de 15 fuentes, evitando un scroll infinito en pantalla e indicando el remanente con un mensaje corto (`... y X fuentes más`).
- **Fix:** Estabilizada la evaluación de variables de estado con la función `choice` que podía fallar al interpretar el nivel de error secuencial.

## v8.1
- **Mejora:** Opción en el countdown final para leer la tecla `ENTER` correctamente en lugar de esperar de manera pasiva gracias a un helper nativo temporal generado con PowerShell.
- **Mejora:** Auto-descarga nativa de `MKVToolNix` en caso de no encontrarse `mkvmerge.exe`.
- **Mejora:** Detección de subtítulos con nomenclatura `forced`, `signs` o `songs` para asignación automática del flag de pista forzada en MKV.
