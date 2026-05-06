@echo off
:: Lanzador para menú "Enviar a" -> Rename-AnimeJellyfin
:: Soporta selección múltiple de carpetas.
:: delayed expansion desactivada para preservar ! en rutas.
:: Paths escritos entre comillas para preservar & y otros caracteres especiales.

:: ---- Ruta absoluta al script PS1 (edítala si mueves los archivos) ----
set "PS1_PATH=C:\Rename-AnimeJellyfin.ps1"

if not exist "%PS1_PATH%" (
    echo.
    echo  ERROR: No se encontro el script PS1 en:
    echo    %PS1_PATH%
    echo.
    echo  Edita la variable PS1_PATH en este .bat
    echo.
    pause
    exit /b 1
)

setlocal disabledelayedexpansion

set "TMP_LIST=%TEMP%\rename_paths_%RANDOM%.txt"
if exist "%TMP_LIST%" del "%TMP_LIST%"

:loop
if "%~1"=="" goto :run
echo "%~1">> "%TMP_LIST%"
shift
goto :loop

:run
PowerShell.exe -NoProfile -ExecutionPolicy Bypass ^
    -File "%PS1_PATH%" ^
    -PathList "%TMP_LIST%"

if exist "%TMP_LIST%" del "%TMP_LIST%"
