@echo off
setlocal enabledelayedexpansion
title SmartMuxer v8.1
mode con: cols=110 lines=42
color 0B

:: ===============================================================================
::  SMART MUXER v8.1
::  Cambios vs v8.0:
::   - ENTER funciona en el countdown final (helper PowerShell para leer teclas).
::   - Auto-descarga de MKVToolNix si falta mkvmerge.exe.
::   - Subs con "forced" / "signs" / "songs" en el nombre se marcan como forced.
::
::  Arrastra al .bat:  1 .mkv base  +  N adjuntos  (video/audio/sub/font/xml)
::  Salida:            <nombre_mkv>_muxed.mkv  (sufijo numerico si ya existe)
:: ===============================================================================

:: ---------- Rutas de helpers temporales ----------
set "TMP_PS_TIMER=%TEMP%\_smartmuxer_timer.ps1"
set "TMP_PS_DOWNLOAD=%TEMP%\_smartmuxer_download.ps1"

:: ---------- Resolver ruta a mkvmerge ----------
set "DEPS_DIR=%~dp0dependencias"
set "MKVMERGE="
if exist "%DEPS_DIR%\mkvmerge.exe" set "MKVMERGE=%DEPS_DIR%\mkvmerge.exe"
if not defined MKVMERGE if exist "%~dp0mkvmerge.exe" set "MKVMERGE=%~dp0mkvmerge.exe"

if not defined MKVMERGE call :OFFER_DOWNLOAD
if not defined MKVMERGE (
    color 4F
    echo.
    echo [ERROR] Sin mkvmerge.exe no puedo continuar.
    pause & exit /b 1
)

if "%~1"=="" goto :MODO_AYUDA

:: ===============================================================================
::  1) Parse de argumentos
:: ===============================================================================
set "ARG_COUNT=0"
:LOOP_PARSE
if "%~1"=="" goto :PARSE_DONE
set /a ARG_COUNT+=1
set "ARG[!ARG_COUNT!]=%~1"
shift
goto :LOOP_PARSE
:PARSE_DONE

if !ARG_COUNT! LSS 2 (
    color 4F
    cls
    echo.
    echo  [ERROR] Necesitas arrastrar al menos 2 archivos:
    echo            - Un .mkv base
    echo            - Uno o mas adjuntos (video/audio/sub/font/xml^)
    echo.
    pause & exit /b 1
)

:: ===============================================================================
::  2) Clasificacion por extension
:: ===============================================================================
set "MKV_BASE="
set "MKV_BASE_COUNT=0"
set "VIDEO_COUNT=0"
set "AUDIO_COUNT=0"
set "SUB_COUNT=0"
set "FONT_COUNT=0"
set "CAPS_COUNT=0"
set "UNKNOWN_COUNT=0"

for /L %%i in (1,1,!ARG_COUNT!) do (
    set "f=!ARG[%%i]!"
    set "ext="
    for %%E in ("!f!") do set "ext=%%~xE"
    if defined ext set "ext=!ext:~1!"

    if /i "!ext!"=="mkv" (
        set /a MKV_BASE_COUNT+=1
        if !MKV_BASE_COUNT! EQU 1 set "MKV_BASE=!f!"
    ) else (
        call :CLASSIFY "!ext!" cat
        if "!cat!"=="VIDEO" (
            set /a VIDEO_COUNT+=1
            set "VIDEO[!VIDEO_COUNT!]=!f!"
        ) else if "!cat!"=="AUDIO" (
            set /a AUDIO_COUNT+=1
            set "AUDIO[!AUDIO_COUNT!]=!f!"
        ) else if "!cat!"=="SUB" (
            set /a SUB_COUNT+=1
            set "SUB[!SUB_COUNT!]=!f!"
        ) else if "!cat!"=="FONT" (
            set /a FONT_COUNT+=1
            set "FONT[!FONT_COUNT!]=!f!"
        ) else if "!cat!"=="CAPS" (
            set /a CAPS_COUNT+=1
            set "CAPS[!CAPS_COUNT!]=!f!"
        ) else (
            set /a UNKNOWN_COUNT+=1
            set "UNKNOWN[!UNKNOWN_COUNT!]=!f!"
        )
    )
)

if !MKV_BASE_COUNT! EQU 0 (
    color 4F
    cls
    echo.
    echo  [ERROR] No detecte ningun .mkv en lo que arrastraste.
    echo.
    pause & exit /b 1
)

if !MKV_BASE_COUNT! GEQ 2 (
    color 6F
    cls
    echo.
    echo  [AVISO] Hay mas de un .mkv. Se usara el primero como base:
    echo            ^> !MKV_BASE!
    echo          Los demas .mkv seran ignorados.
    echo.
    pause
    color 0B
)

:: ===============================================================================
::  3) Analizar pistas existentes en el mkv base
:: ===============================================================================
set "BASE_AUDIO_COUNT=0"
set "BASE_SUB_COUNT=0"
for /f "usebackq tokens=*" %%L in (`""%MKVMERGE%" -i "!MKV_BASE!" 2^>nul"`) do (
    echo %%L | findstr /C:"audio (" >nul && set /a BASE_AUDIO_COUNT+=1
    echo %%L | findstr /C:"subtitles (" >nul && set /a BASE_SUB_COUNT+=1
)

:: ===============================================================================
::  4) Resumen inicial
:: ===============================================================================
cls
echo.
echo ===============================================================================
echo                       SMART MUXER v8.1  -  RESUMEN
echo ===============================================================================
echo.
for %%F in ("!MKV_BASE!") do set "MKV_BASE_NAME=%%~nxF"
echo  [MKV BASE]  (!BASE_AUDIO_COUNT! audio/s  -  !BASE_SUB_COUNT! sub/s existentes^)
echo    ^> !MKV_BASE_NAME!
echo.
echo  ---------------------------- ADJUNTOS DETECTADOS -----------------------------
echo.

if !VIDEO_COUNT! GTR 0 (
    echo   [VIDEO]      ^(!VIDEO_COUNT!^)  - reemplazara el video del mkv
    for /L %%i in (1,1,!VIDEO_COUNT!) do for %%F in ("!VIDEO[%%i]!") do echo       %%i. %%~nxF
    echo.
)
if !AUDIO_COUNT! GTR 0 (
    echo   [AUDIO]      ^(!AUDIO_COUNT!^)  - se anadiran al mkv
    for /L %%i in (1,1,!AUDIO_COUNT!) do for %%F in ("!AUDIO[%%i]!") do echo       %%i. %%~nxF
    echo.
)
if !SUB_COUNT! GTR 0 (
    echo   [SUBTITULO]  ^(!SUB_COUNT!^)  - se anadiran al mkv
    for /L %%i in (1,1,!SUB_COUNT!) do for %%F in ("!SUB[%%i]!") do echo       %%i. %%~nxF
    echo.
)
if !FONT_COUNT! GTR 0 (
    echo   [FONT]       ^(!FONT_COUNT!^)  - se adjuntaran al mkv
    for /L %%i in (1,1,!FONT_COUNT!) do for %%F in ("!FONT[%%i]!") do echo       %%i. %%~nxF
    echo.
)
if !CAPS_COUNT! GTR 0 (
    echo   [CAPITULOS]  ^(!CAPS_COUNT!^)  - reemplazaran los capitulos del mkv
    for /L %%i in (1,1,!CAPS_COUNT!) do for %%F in ("!CAPS[%%i]!") do echo       %%i. %%~nxF
    echo.
)
if !UNKNOWN_COUNT! GTR 0 (
    color 6F
    echo   [NO RECONOCIDOS] ^(!UNKNOWN_COUNT!^) - se ignoraran:
    for /L %%i in (1,1,!UNKNOWN_COUNT!) do for %%F in ("!UNKNOWN[%%i]!") do echo       - %%~nxF
    echo.
    color 0B
)

set /a TOTAL_PROC=VIDEO_COUNT+AUDIO_COUNT+SUB_COUNT+FONT_COUNT+CAPS_COUNT
if !TOTAL_PROC! EQU 0 (
    color 4F
    echo  [ERROR] No hay nada valido para procesar.
    pause & exit /b 1
)

echo ===============================================================================
choice /C SN /N /M "  Continuar con la seleccion paso a paso? [S/N] "
if errorlevel 2 exit /b

:: ===============================================================================
::  5) Pipeline de seleccion
:: ===============================================================================
set "SEL_VIDEO="
set "SEL_AUDIOS="
set "SEL_SUBS="
set "SEL_FONTS="
set "SEL_CAPS="
set "REPLACE_AUDIO=0"
set "REPLACE_SUBS=0"

if !VIDEO_COUNT! GEQ 1 call :SELECT_SINGLE VIDEO "fuente de video (reemplaza el video del mkv)" SEL_VIDEO

if !AUDIO_COUNT! GEQ 1 (
    for /L %%i in (1,1,!AUDIO_COUNT!) do call :ASK_ADD_TRACK AUDIO %%i "audio"
)
if defined SEL_AUDIOS if !BASE_AUDIO_COUNT! GEQ 1 (
    cls
    echo.
    echo ===============================================================================
    echo  El MKV ya tiene !BASE_AUDIO_COUNT! pista/s de audio existentes.
    echo  Vas a anadir nuevos audios.
    echo ===============================================================================
    echo.
    echo   [C] Conservar audios existentes (sumar los nuevos^)
    echo   [R] Reemplazar audios existentes (solo quedan los nuevos^)
    echo.
    choice /C CR /N /M "  Opcion: "
    if errorlevel 2 set "REPLACE_AUDIO=1"
)

if !SUB_COUNT! GEQ 1 (
    for /L %%i in (1,1,!SUB_COUNT!) do call :ASK_ADD_TRACK SUB %%i "subtitulo"
)
if defined SEL_SUBS if !BASE_SUB_COUNT! GEQ 1 (
    cls
    echo.
    echo ===============================================================================
    echo  El MKV ya tiene !BASE_SUB_COUNT! pista/s de subtitulos existentes.
    echo  Vas a anadir nuevos subtitulos.
    echo ===============================================================================
    echo.
    echo   [C] Conservar subtitulos existentes (sumar los nuevos^)
    echo   [R] Reemplazar subtitulos existentes (solo quedan los nuevos^)
    echo.
    choice /C CR /N /M "  Opcion: "
    if errorlevel 2 set "REPLACE_SUBS=1"
)

if !FONT_COUNT! GEQ 1 (
    cls
    echo.
    echo ===============================================================================
    echo  FONTS detectadas: !FONT_COUNT!
    echo ===============================================================================
    for /L %%i in (1,1,!FONT_COUNT!) do for %%F in ("!FONT[%%i]!") do echo    - %%~nxF
    echo.
    choice /C SN /N /M "  Adjuntar todas las fonts al mkv? [S/N] "
    if errorlevel 1 set "SEL_FONTS=1"
    if errorlevel 2 set "SEL_FONTS="
)

if !CAPS_COUNT! GEQ 1 call :SELECT_SINGLE CAPS "archivo de capitulos (reemplaza los existentes)" SEL_CAPS

:: ===============================================================================
::  6) Confirmacion final con ENTER funcional
:: ===============================================================================
cls
echo.
echo ===============================================================================
echo                  SMART MUXER v8.1  -  CONFIRMACION FINAL
echo ===============================================================================
echo.
echo  MKV BASE:  !MKV_BASE_NAME!
echo.
echo  ACCIONES:
echo.
if defined SEL_VIDEO for %%F in ("!SEL_VIDEO!") do echo    [+] Reemplazar video por:  %%~nxF
if defined SEL_AUDIOS (
    if "!REPLACE_AUDIO!"=="1" (echo    [*] Reemplazar audios existentes) else (echo    [=] Conservar audios existentes)
    for %%i in (!SEL_AUDIOS!) do for %%F in ("!AUDIO[%%i]!") do echo    [+] Anadir audio:    [!AUDIO_LANG[%%i]!]  %%~nxF
)
if defined SEL_SUBS (
    if "!REPLACE_SUBS!"=="1" (echo    [*] Reemplazar subtitulos existentes) else (echo    [=] Conservar subtitulos existentes)
    for %%i in (!SEL_SUBS!) do (
        set "_tag="
        if "!SUB_FORCED[%%i]!"=="1" set "_tag= [forced]"
        for %%F in ("!SUB[%%i]!") do echo    [+] Anadir sub:      [!SUB_LANG[%%i]!]!_tag!  %%~nxF
    )
)
if defined SEL_FONTS echo    [+] Adjuntar !FONT_COUNT! font/s
if defined SEL_CAPS for %%F in ("!SEL_CAPS!") do echo    [+] Reemplazar capitulos por:  %%~nxF
echo.

set "_HAS_ACTION=0"
if defined SEL_VIDEO  set "_HAS_ACTION=1"
if defined SEL_AUDIOS set "_HAS_ACTION=1"
if defined SEL_SUBS   set "_HAS_ACTION=1"
if defined SEL_FONTS  set "_HAS_ACTION=1"
if defined SEL_CAPS   set "_HAS_ACTION=1"
if "!_HAS_ACTION!"=="0" (
    color 4F
    echo  [ERROR] No seleccionaste ninguna accion. Saliendo.
    pause & exit /b
)

call :BUILD_OUTPUT_NAME "!MKV_BASE!" OUTPUT_FILE
for %%F in ("!OUTPUT_FILE!") do set "OUTPUT_NAME=%%~nxF"
echo  SALIDA:    !OUTPUT_NAME!
echo.
echo ===============================================================================

:: Aqui esta el fix: PowerShell helper acepta ENTER, Y, o X
call :TIMED_CONFIRM 15 _FINAL_KEY
if /i "!_FINAL_KEY!"=="X" (
    echo.
    echo  Cancelado por el usuario.
    timeout /t 2 >nul
    exit /b
)

:: ===============================================================================
::  7) Construir y ejecutar
:: ===============================================================================
cls
echo.
echo [PROCESANDO] Ejecutando mkvmerge...
echo --------------------------------------------------------------------------------
echo.

set "BASE_FLAGS="
if defined SEL_VIDEO              set "BASE_FLAGS=!BASE_FLAGS! --no-video"
if "!REPLACE_AUDIO!"=="1"         set "BASE_FLAGS=!BASE_FLAGS! --no-audio"
if "!REPLACE_SUBS!"=="1"          set "BASE_FLAGS=!BASE_FLAGS! --no-subtitles"
if defined SEL_CAPS               set "BASE_FLAGS=!BASE_FLAGS! --no-chapters"

set "VIDEO_ARG="
if defined SEL_VIDEO set VIDEO_ARG="!SEL_VIDEO!"

set "AUDIO_CMD="
if defined SEL_AUDIOS (
    set "_first_audio=1"
    for %%i in (!SEL_AUDIOS!) do (
        set "_def=no"
        if "!REPLACE_AUDIO!"=="1" if "!_first_audio!"=="1" set "_def=yes"
        set AUDIO_CMD=!AUDIO_CMD! --language 0:!AUDIO_LANG[%%i]! --default-track 0:!_def! "!AUDIO[%%i]!"
        set "_first_audio=0"
    )
)

set "SUB_CMD="
if defined SEL_SUBS (
    set "_first_sub=1"
    for %%i in (!SEL_SUBS!) do (
        set "_def=no"
        if "!REPLACE_SUBS!"=="1" if "!_first_sub!"=="1" set "_def=yes"
        set "_forced=no"
        if "!SUB_FORCED[%%i]!"=="1" set "_forced=yes"
        set SUB_CMD=!SUB_CMD! --language 0:!SUB_LANG[%%i]! --default-track 0:!_def! --forced-track 0:!_forced! "!SUB[%%i]!"
        set "_first_sub=0"
    )
)

set "FONT_CMD="
if defined SEL_FONTS (
    for /L %%i in (1,1,!FONT_COUNT!) do (
        set FONT_CMD=!FONT_CMD! --attach-file "!FONT[%%i]!"
    )
)

set "CAPS_CMD="
if defined SEL_CAPS set CAPS_CMD=--chapters "!SEL_CAPS!"

"%MKVMERGE%" -o "!OUTPUT_FILE!" --no-global-tags --no-track-tags !BASE_FLAGS! "!MKV_BASE!" !VIDEO_ARG! !AUDIO_CMD! !SUB_CMD! !FONT_CMD! !CAPS_CMD!
set "MKV_EXIT=!errorlevel!"

:: Limpiar helpers temporales
if exist "%TMP_PS_TIMER%" del "%TMP_PS_TIMER%" >nul 2>&1

echo.
if !MKV_EXIT! EQU 0 (
    color 2F
    echo ===============================================================================
    echo  EXITO - Archivo generado:
    echo    !OUTPUT_FILE!
    echo ===============================================================================
    timeout /t 6 >nul
) else if !MKV_EXIT! EQU 1 (
    color 6F
    echo ===============================================================================
    echo  COMPLETADO CON ADVERTENCIAS - Archivo generado:
    echo    !OUTPUT_FILE!
    echo ===============================================================================
    pause
) else (
    color 4F
    echo ===============================================================================
    echo  ERROR - mkvmerge fallo (codigo !MKV_EXIT!^).
    echo ===============================================================================
    pause
)
exit /b


:: ===============================================================================
::  SUBRUTINAS
:: ===============================================================================

:CLASSIFY <ext> <outVar>
set "_e=%~1"
set "_cat=UNKNOWN"
for %%X in (mp4 m4v avi mov h264 hevc h265 264 265 ts m2ts mts webm wmv flv mpg mpeg vob ogv ogm 3gp y4m) do if /i "%_e%"=="%%X" set "_cat=VIDEO"
for %%X in (mka flac ac3 eac3 dts dtshd dtsma aac opus mp3 mp2 m4a wav thd truehd ogg oga wv ape mlp aiff) do if /i "%_e%"=="%%X" set "_cat=AUDIO"
for %%X in (ass srt ssa sub sup idx vtt pgs) do if /i "%_e%"=="%%X" set "_cat=SUB"
for %%X in (ttf otf woff woff2 ttc) do if /i "%_e%"=="%%X" set "_cat=FONT"
for %%X in (xml) do if /i "%_e%"=="%%X" set "_cat=CAPS"
set "%~2=%_cat%"
exit /b

:DETECT_LANG <filepath> <outVar>
setlocal enabledelayedexpansion
set "fp=%~1"
for %%F in ("!fp!") do set "fname=%%~nF"
set "subext="
for /f "delims=" %%L in ('powershell -nop -c "$n='!fname!'; $i=$n.LastIndexOf('.'); if($i -gt 0){ $n.Substring($i+1).ToLower() } else { '' }"') do set "subext=%%L"

set "lang=und"
if /i "!subext!"=="es"     set "lang=spa"
if /i "!subext!"=="spa"    set "lang=spa"
if /i "!subext!"=="esp"    set "lang=spa"
if /i "!subext!"=="lat"    set "lang=spa"
if /i "!subext!"=="es-419" set "lang=spa"
if /i "!subext!"=="es-es"  set "lang=spa"
if /i "!subext!"=="en"     set "lang=eng"
if /i "!subext!"=="eng"    set "lang=eng"
if /i "!subext!"=="ja"     set "lang=jpn"
if /i "!subext!"=="jpn"    set "lang=jpn"
if /i "!subext!"=="jp"     set "lang=jpn"
if /i "!subext!"=="pt"     set "lang=por"
if /i "!subext!"=="por"    set "lang=por"
if /i "!subext!"=="pt-br"  set "lang=por"
if /i "!subext!"=="br"     set "lang=por"
if /i "!subext!"=="fr"     set "lang=fre"
if /i "!subext!"=="fra"    set "lang=fre"
if /i "!subext!"=="fre"    set "lang=fre"
if /i "!subext!"=="de"     set "lang=ger"
if /i "!subext!"=="ger"    set "lang=ger"
if /i "!subext!"=="deu"    set "lang=ger"
if /i "!subext!"=="it"     set "lang=ita"
if /i "!subext!"=="ita"    set "lang=ita"
if /i "!subext!"=="ru"     set "lang=rus"
if /i "!subext!"=="rus"    set "lang=rus"
if /i "!subext!"=="zh"     set "lang=chi"
if /i "!subext!"=="chi"    set "lang=chi"
if /i "!subext!"=="zho"    set "lang=chi"
if /i "!subext!"=="ko"     set "lang=kor"
if /i "!subext!"=="kor"    set "lang=kor"
if /i "!subext!"=="ar"     set "lang=ara"
if /i "!subext!"=="ara"    set "lang=ara"

endlocal & set "%~2=%lang%"
exit /b

:DETECT_FORCED <filepath> <outVar>
:: Devuelve 1 si el nombre contiene "forced", "signs" o "songs" como palabra/token.
setlocal enabledelayedexpansion
set "fp=%~1"
for %%F in ("!fp!") do set "fname=%%~nxF"

:: Buscar palabras clave (case-insensitive, /i en findstr)
set "_is_forced=0"
echo !fname! | findstr /i /R "\<forced\>" >nul && set "_is_forced=1"
echo !fname! | findstr /i /R "\<signs\>"  >nul && set "_is_forced=1"
echo !fname! | findstr /i /R "\<songs\>"  >nul && set "_is_forced=1"
:: Tambien chequear sin word-boundary (algunos nombres no usan separadores)
echo !fname! | findstr /i /C:".forced." >nul && set "_is_forced=1"
echo !fname! | findstr /i /C:".signs."  >nul && set "_is_forced=1"
echo !fname! | findstr /i /C:".songs."  >nul && set "_is_forced=1"

endlocal & set "%~2=%_is_forced%"
exit /b

:ASK_LANG <outVar>
cls
echo.
echo ===============================================================================
echo  No pude detectar el idioma desde el nombre. Selecciona:
echo ===============================================================================
echo.
echo    [1] Espanol (spa^)        [2] Ingles (eng^)
echo    [3] Japones (jpn^)        [4] Portugues (por^)
echo    [5] Frances (fre^)        [6] Aleman (ger^)
echo    [7] Italiano (ita^)       [8] Coreano (kor^)
echo    [9] Chino (chi^)          [0] Indeterminado (und^)
echo.
choice /C 1234567890 /N /M "  Opcion: "
set "rc=!errorlevel!"
set "_lng=und"
if !rc! EQU 1 set "_lng=spa"
if !rc! EQU 2 set "_lng=eng"
if !rc! EQU 3 set "_lng=jpn"
if !rc! EQU 4 set "_lng=por"
if !rc! EQU 5 set "_lng=fre"
if !rc! EQU 6 set "_lng=ger"
if !rc! EQU 7 set "_lng=ita"
if !rc! EQU 8 set "_lng=kor"
if !rc! EQU 9 set "_lng=chi"
if !rc! EQU 10 set "_lng=und"
set "%~1=%_lng%"
exit /b

:ASK_ADD_TRACK <prefix> <index> <typeDesc>
set "pref=%~1"
set "idx=%~2"
set "tdesc=%~3"

call set "fpath=%%!pref![!idx!]%%"
call set "totalcnt=%%!pref!_COUNT%%"
for %%F in ("!fpath!") do set "fname=%%~nxF"

:: Detectar forced (solo si es SUB)
set "_forced=0"
if /i "!pref!"=="SUB" call :DETECT_FORCED "!fpath!" _forced

cls
echo.
echo ===============================================================================
echo  ANADIR !tdesc!  ^(!idx!/!totalcnt!^)?
echo ===============================================================================
echo.
echo    ^> !fname!
if "!_forced!"=="1" echo      ^(detectado como subtitulo "forced/signs/songs"^)
echo.
choice /C SN /N /M "  Anadir esta pista? [S/N] "
if errorlevel 2 exit /b

call :DETECT_LANG "!fpath!" _detected
if /i "!_detected!"=="und" call :ASK_LANG _detected

if /i "!pref!"=="AUDIO" (
    if defined SEL_AUDIOS (set "SEL_AUDIOS=!SEL_AUDIOS! !idx!") else (set "SEL_AUDIOS=!idx!")
    set "AUDIO_LANG[!idx!]=!_detected!"
) else (
    if defined SEL_SUBS (set "SEL_SUBS=!SEL_SUBS! !idx!") else (set "SEL_SUBS=!idx!")
    set "SUB_LANG[!idx!]=!_detected!"
    set "SUB_FORCED[!idx!]=!_forced!"
)
exit /b

:SELECT_SINGLE <prefix> <description> <outVar>
set "pref=%~1"
set "desc=%~2"
call set "cnt=%%!pref!_COUNT%%"

if !cnt! EQU 1 (
    call set "fpath=%%!pref![1]%%"
    for %%F in ("!fpath!") do set "fname=%%~nxF"
    cls
    echo.
    echo ===============================================================================
    echo  USAR !desc!?
    echo ===============================================================================
    echo.
    echo    ^> !fname!
    echo.
    choice /C SN /N /M "  Confirmar? [S/N] "
    if errorlevel 2 (set "%~3=" & exit /b)
    set "%~3=!fpath!"
    exit /b
)

:SS_RETRY
cls
echo.
echo ===============================================================================
echo  Hay !cnt! !desc!. Cual usar?
echo ===============================================================================
echo.
for /L %%i in (1,1,!cnt!) do (
    call set "fp=%%!pref![%%i]%%"
    for %%F in ("!fp!") do echo    [%%i] %%~nxF
)
echo    [0] Omitir (no usar ninguno^)
echo.
set "opt="
set /p "opt=  Numero: "
if not defined opt goto :SS_RETRY
if "!opt!"=="0" (set "%~3=" & exit /b)
set /a _check=opt 2>nul
if "!_check!"=="0" goto :SS_RETRY
if !_check! LSS 1 goto :SS_RETRY
if !_check! GTR !cnt! goto :SS_RETRY
call set "chosen=%%!pref![!_check!]%%"
set "%~3=!chosen!"
exit /b

:BUILD_OUTPUT_NAME <inputMkv> <outVar>
set "in=%~1"
for %%F in ("!in!") do (
    set "dir=%%~dpF"
    set "base=%%~nF"
)
set "candidate=!dir!!base!_muxed.mkv"
set "n=1"
:BON_LOOP
if exist "!candidate!" (
    set /a n+=1
    set "candidate=!dir!!base!_muxed_!n!.mkv"
    goto :BON_LOOP
)
set "%~2=!candidate!"
exit /b

:: ===============================================================================
::  Helper: TIMED_CONFIRM con ENTER (genera y ejecuta script PowerShell)
:: ===============================================================================
:TIMED_CONFIRM <timeoutSecs> <outVar>
:: Devuelve "Y" si ENTER/Y o timeout. Devuelve "X" si X.
call :WRITE_PS_TIMER
for /f "delims=" %%K in ('powershell -nop -ExecutionPolicy Bypass -File "%TMP_PS_TIMER%" %~1') do set "_TC_RES=%%K"
set "%~2=%_TC_RES%"
exit /b

:WRITE_PS_TIMER
:: Escribe el script .ps1 helper. Se regenera siempre (es chico).
> "%TMP_PS_TIMER%" echo param^([double]$t^)
>> "%TMP_PS_TIMER%" echo $c = ''
>> "%TMP_PS_TIMER%" echo $start = Get-Date
>> "%TMP_PS_TIMER%" echo while ^($true^) {
>> "%TMP_PS_TIMER%" echo     $elapsed = ^(^(Get-Date^) - $start^).TotalSeconds
>> "%TMP_PS_TIMER%" echo     $remaining = $t - $elapsed
>> "%TMP_PS_TIMER%" echo     if ^($remaining -le 0^) { $c = 'Y'; break }
>> "%TMP_PS_TIMER%" echo     $secs = [int][Math]::Ceiling^($remaining^)
>> "%TMP_PS_TIMER%" echo     $msg = "  Auto-inicio en {0,2}s   [ENTER/Y = Procesar   X = Cancelar]   " -f $secs
>> "%TMP_PS_TIMER%" echo     [Console]::Error.Write^([char]13 + $msg^)
>> "%TMP_PS_TIMER%" echo     if ^([Console]::KeyAvailable^) {
>> "%TMP_PS_TIMER%" echo         $k = [Console]::ReadKey^($true^)
>> "%TMP_PS_TIMER%" echo         if ^($k.Key -eq 'Enter'^) { $c = 'Y'; break }
>> "%TMP_PS_TIMER%" echo         if ^($k.KeyChar -eq 'Y' -or $k.KeyChar -eq 'y'^) { $c = 'Y'; break }
>> "%TMP_PS_TIMER%" echo         if ^($k.KeyChar -eq 'X' -or $k.KeyChar -eq 'x'^) { $c = 'X'; break }
>> "%TMP_PS_TIMER%" echo     }
>> "%TMP_PS_TIMER%" echo     Start-Sleep -Milliseconds 100
>> "%TMP_PS_TIMER%" echo }
>> "%TMP_PS_TIMER%" echo [Console]::Error.WriteLine^(^)
>> "%TMP_PS_TIMER%" echo Write-Output $c
exit /b

:: ===============================================================================
::  Helper: Auto-descarga de dependencias
:: ===============================================================================
:OFFER_DOWNLOAD
cls
echo.
echo ===============================================================================
echo                       SMART MUXER v8.1
echo                    Falta dependencia: mkvmerge.exe
echo ===============================================================================
echo.
echo  No encontre mkvmerge.exe ni en la carpeta del .bat ni en \dependencias.
echo.
echo  Puedo descargarlo automaticamente desde el sitio oficial:
echo.
echo    Origen:   https://mkvtoolnix.download   (sitio oficial^)
echo    Tamano:   ~30 MB (MKVToolNix portable .7z^) + ~600 KB (7zr.exe^)
echo    Destino:  %DEPS_DIR%
echo.
echo ===============================================================================
choice /C SN /N /M "  Descargar automaticamente? [S/N] "
if errorlevel 2 (
    cls
    echo.
    echo ===============================================================================
    echo  INSTALACION MANUAL
    echo ===============================================================================
    echo.
    echo  1. Descarga MKVToolNix portable 64-bit (.7z^) desde:
    echo       https://mkvtoolnix.download/downloads.html
    echo.
    echo  2. Extrae el contenido (con 7-Zip o similar^).
    echo.
    echo  3. Copia mkvmerge.exe (y los .dll que lo acompanen^) a:
    echo       %DEPS_DIR%
    echo     o bien a la carpeta donde esta este .bat.
    echo.
    echo  4. Vuelve a ejecutar SmartMuxer.
    echo.
    pause
    exit /b
)
call :DOWNLOAD_DEPS
exit /b

:DOWNLOAD_DEPS
if not exist "%DEPS_DIR%" mkdir "%DEPS_DIR%"
call :WRITE_PS_DOWNLOAD

cls
echo.
echo ===============================================================================
echo  Descargando dependencias...
echo ===============================================================================
echo.

powershell -nop -ExecutionPolicy Bypass -File "%TMP_PS_DOWNLOAD%" "%DEPS_DIR%"
set "DL_EXIT=!errorlevel!"
del "%TMP_PS_DOWNLOAD%" >nul 2>&1

if !DL_EXIT! NEQ 0 (
    color 4F
    echo.
    echo [ERROR] La descarga fallo (codigo !DL_EXIT!^).
    echo Verifica tu conexion y vuelve a intentar.
    echo.
    pause
    exit /b
)

if exist "%DEPS_DIR%\mkvmerge.exe" (
    set "MKVMERGE=%DEPS_DIR%\mkvmerge.exe"
    color 2F
    echo.
    echo [OK] Dependencias instaladas en: %DEPS_DIR%
    color 0B
    timeout /t 3 >nul
) else (
    color 4F
    echo.
    echo [ERROR] No encuentro mkvmerge.exe en %DEPS_DIR% despues de la descarga.
    pause
    exit /b
)
exit /b

:WRITE_PS_DOWNLOAD
> "%TMP_PS_DOWNLOAD%" echo $ErrorActionPreference = 'Stop'
>> "%TMP_PS_DOWNLOAD%" echo [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
>> "%TMP_PS_DOWNLOAD%" echo $depsDir = $args[0]
>> "%TMP_PS_DOWNLOAD%" echo Write-Host ''
>> "%TMP_PS_DOWNLOAD%" echo Write-Host '[1/4] Descargando 7zr.exe (extractor 7z)...' -ForegroundColor Cyan
>> "%TMP_PS_DOWNLOAD%" echo $7zr = Join-Path $depsDir '7zr.exe'
>> "%TMP_PS_DOWNLOAD%" echo Invoke-WebRequest -Uri 'https://www.7-zip.org/a/7zr.exe' -OutFile $7zr -UseBasicParsing
>> "%TMP_PS_DOWNLOAD%" echo Write-Host '      OK' -ForegroundColor Green
>> "%TMP_PS_DOWNLOAD%" echo Write-Host ''
>> "%TMP_PS_DOWNLOAD%" echo Write-Host '[2/4] Detectando ultima version de MKVToolNix...' -ForegroundColor Cyan
>> "%TMP_PS_DOWNLOAD%" echo $page = Invoke-WebRequest -Uri 'https://mkvtoolnix.download/downloads.html' -UseBasicParsing
>> "%TMP_PS_DOWNLOAD%" echo if ^($page.Content -match 'mkvtoolnix-64-bit-^(\d+\.\d+^(\.\d+^)?^)\.7z'^) {
>> "%TMP_PS_DOWNLOAD%" echo     $ver = $matches[1]
>> "%TMP_PS_DOWNLOAD%" echo     Write-Host "      Version detectada: $ver" -ForegroundColor Green
>> "%TMP_PS_DOWNLOAD%" echo } else {
>> "%TMP_PS_DOWNLOAD%" echo     throw 'No se pudo detectar la version de MKVToolNix.'
>> "%TMP_PS_DOWNLOAD%" echo }
>> "%TMP_PS_DOWNLOAD%" echo $mkvUrl = "https://mkvtoolnix.download/windows/releases/$ver/mkvtoolnix-64-bit-$ver.7z"
>> "%TMP_PS_DOWNLOAD%" echo $7zFile = Join-Path $depsDir 'mkvtoolnix.7z'
>> "%TMP_PS_DOWNLOAD%" echo Write-Host ''
>> "%TMP_PS_DOWNLOAD%" echo Write-Host "[3/4] Descargando MKVToolNix $ver (~30 MB)..." -ForegroundColor Cyan
>> "%TMP_PS_DOWNLOAD%" echo $ProgressPreference = 'SilentlyContinue'
>> "%TMP_PS_DOWNLOAD%" echo Invoke-WebRequest -Uri $mkvUrl -OutFile $7zFile -UseBasicParsing
>> "%TMP_PS_DOWNLOAD%" echo Write-Host '      OK' -ForegroundColor Green
>> "%TMP_PS_DOWNLOAD%" echo Write-Host ''
>> "%TMP_PS_DOWNLOAD%" echo Write-Host '[4/4] Extrayendo...' -ForegroundColor Cyan
>> "%TMP_PS_DOWNLOAD%" echo ^& $7zr x $7zFile "-o$depsDir" -y ^| Out-Null
>> "%TMP_PS_DOWNLOAD%" echo if ^($LASTEXITCODE -ne 0^) { throw "7zr fallo con codigo $LASTEXITCODE" }
>> "%TMP_PS_DOWNLOAD%" echo $sub = Get-ChildItem -Path $depsDir -Directory ^| Where-Object { $_.Name -like 'mkvtoolnix*' } ^| Select-Object -First 1
>> "%TMP_PS_DOWNLOAD%" echo if ^($sub^) {
>> "%TMP_PS_DOWNLOAD%" echo     Get-ChildItem -Path $sub.FullName -Recurse -File ^| Where-Object { $_.Extension -in '.exe', '.dll' } ^| ForEach-Object { Move-Item -Path $_.FullName -Destination $depsDir -Force -ErrorAction SilentlyContinue }
>> "%TMP_PS_DOWNLOAD%" echo     Remove-Item -Path $sub.FullName -Recurse -Force -ErrorAction SilentlyContinue
>> "%TMP_PS_DOWNLOAD%" echo }
>> "%TMP_PS_DOWNLOAD%" echo Remove-Item $7zFile -Force -ErrorAction SilentlyContinue
>> "%TMP_PS_DOWNLOAD%" echo Write-Host '      OK' -ForegroundColor Green
>> "%TMP_PS_DOWNLOAD%" echo Write-Host ''
>> "%TMP_PS_DOWNLOAD%" echo Write-Host 'Listo!' -ForegroundColor Green
exit /b

:MODO_AYUDA
cls
echo.
echo ===============================================================================
echo                     SMART MUXER v8.1  -  AYUDA
echo ===============================================================================
echo.
echo   USO:  Arrastra JUNTOS los archivos sobre este .bat:
echo           - 1 archivo .mkv (base a modificar^)
echo           - 1 o mas adjuntos:
echo               * Video    (mp4, m4v, avi, mov, h264, hevc, ts, m2ts, webm...^)
echo               * Audio    (mka, flac, ac3, eac3, dts, aac, opus, mp3, m4a...^)
echo               * Sub      (.ass, .srt, .ssa, .sub, .sup, .vtt...^)
echo               * Font     (.ttf, .otf, .woff, .woff2, .ttc^)
echo               * Caps     (.xml de capitulos^)
echo.
echo   DETECCION DE IDIOMA:
echo           Si el nombre incluye .es.ass / .eng.srt / .jpn.mka el idioma
echo           se detecta automaticamente. Si no, se preguntara.
echo.
echo   DETECCION DE FORCED:
echo           Subs con "forced", "signs" o "songs" en el nombre se marcan
echo           automaticamente como pista forced.
echo.
echo   DEPENDENCIAS:
echo           Si falta mkvmerge.exe, el script ofrece descargarlo desde
echo           https://mkvtoolnix.download (sitio oficial^).
echo.
echo   SALIDA:  ^<nombre_mkv^>_muxed.mkv en la misma carpeta del mkv.
echo.
echo ===============================================================================
pause
exit /b
