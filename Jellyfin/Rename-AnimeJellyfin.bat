@echo off
:: Lanzador para menú "Enviar a" -> Rename-AnimeJellyfin
:: Soporta selección múltiple de carpetas.
:: NOTA: delayed expansion desactivada a propósito para preservar
::       caracteres especiales en rutas (!, ^, &, etc.)

:: ---- Ruta absoluta al script PS1 (edítala si mueves los archivos) ----
set "PS1_PATH=C:\Rename-AnimeJellyfin.ps1"

:: Verificar que el script exista
if not exist "%PS1_PATH%" (
    echo.
    echo  ERROR: No se encontro el script PS1 en:
    echo    %PS1_PATH%
    echo.
    echo  Edita la variable PS1_PATH en este .bat para apuntar a la
    echo  ubicacion correcta del archivo Rename-AnimeJellyfin.ps1
    echo.
    pause
    exit /b 1
)

setlocal disabledelayedexpansion

set "TMP_LIST=%TEMP%\rename_paths_%RANDOM%.txt"
if exist "%TMP_LIST%" del "%TMP_LIST%"

:loop
if "%~1"=="" goto :run
echo %~1>> "%TMP_LIST%"
shift
goto :loop

:run
PowerShell.exe -NoProfile -ExecutionPolicy Bypass ^
    -File "%PS1_PATH%" ^
    -PathList "%TMP_LIST%"

if exist "%TMP_LIST%" del "%TMP_LIST%"
