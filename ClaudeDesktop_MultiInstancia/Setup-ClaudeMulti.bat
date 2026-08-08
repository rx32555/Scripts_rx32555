@echo off
setlocal
title Claude Desktop - Multi Instancia

rem ---------------------------------------------------------------------
rem  Lanzador de Setup-ClaudeMulti.ps1
rem  Ejecuta el script de PowerShell que esta en esta misma carpeta.
rem  Si la instalacion de Claude es MSIX (Microsoft Store), este .cmd
rem  debe correrse como Administrador (boton derecho -> Ejecutar como
rem  administrador). En instalaciones normales NO hace falta admin.
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
echo  Ejecutando configuracion...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*

echo.
pause
endlocal
