@echo off
setlocal
title Claude Desktop - Multi Instancia

rem ---------------------------------------------------------------------
rem  Lanzador de Setup-ClaudeMulti.ps1
rem  Ejecuta el script de PowerShell que esta en esta misma carpeta.
rem
rem  Se puede ejecutar cuantas veces se quiera: en cada arranque comprueba
rem  si Claude Desktop se actualizo y, si es asi, refresca la copia
rem  portable sola. Si ya esta al dia, termina en un segundo sin copiar.
rem
rem  Normalmente NO hace falta Administrador. Solo si la copia falla por
rem  los permisos de WindowsApps el script lo pedira explicitamente.
rem ---------------------------------------------------------------------

set "PS1=%~dp0Setup-ClaudeMulti.ps1"

if not exist "%PS1%" (
    echo.
    echo  [X] No se encontro Setup-ClaudeMulti.ps1 junto a este archivo.
    echo      Deja los dos archivos en la misma carpeta y vuelve a intentar.
    echo.
    pause
    exit /b 1
)

echo.
echo  Configurando / comprobando actualizaciones de Claude...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*

if errorlevel 1 (
    echo.
    echo  [X] Termino con errores. Revisa los mensajes de arriba.
)

echo.
pause
endlocal
