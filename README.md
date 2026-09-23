# Scripts_rx32555

Repositorio personal para gestionar scripts, listas de configuración y herramientas de automatización.

---

## 📂 Contenido del Repositorio

| Carpeta / Herramienta | Descripción | Entorno / Lenguaje |
|-----------------------|-------------|-------------------|
| [**Android_Xiaomi_HyperOS**](./Android_Xiaomi_HyperOS/) | Lista de debloat y optimización para Xiaomi / POCO (probada en POCO F7 Pro con HyperOS 3.x / Android 16) compatible con Canta y Shizuku (sin root). | JSON / Markdown |
| [**Jellyfin**](./Jellyfin/) | `Rename-AnimeJellyfin`: Script para normalizar y renombrar episodios de anime al formato `SxxExx` requerido por Jellyfin. Integrado con el menú contextual "Enviar a" de Windows. | PowerShell 5.1+ / Batch |
| [**Multimedia**](./Multimedia/) | `SmartMuxer`: Script interactivo por lotes para inyección y multiplexado inteligente de pistas de audio, subtítulos, fuentes tipográficas y capítulos en archivos MKV mediante MKVToolNix (`mkvmerge`). | Batch / PowerShell |

---

## 🛠️ Requisitos Generales

- **Sistema Operativo:** Windows 10 / 11 (para herramientas PowerShell y Batch).
- **Consola:** Windows PowerShell 5.1 (incluido por defecto en Windows) o PowerShell 7+.
- **Herramientas externas:** Consultar el `README.md` dentro de cada subcarpeta para detalles de dependencias específicas (ADB, Canta, Shizuku, MKVToolNix, etc.).

---

## 📄 Licencia

Este repositorio se distribuye bajo la licencia [MIT](./LICENSE).
