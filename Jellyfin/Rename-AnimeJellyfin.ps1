<#
.SYNOPSIS
    Renombra archivos de anime al formato Jellyfin (SxxExx).
    Soporta selección múltiple. Cada carpeta procesada guarda su propio
    "_rename_undo.json" para poder deshacer cambios por separado.
#>

param(
    [string[]] $Path       = @(),
    [string]   $PathList   = '',
    [string[]] $Extensions = @('mkv','mp4','avi')
)

# StrictMode desactivado a propósito: causaba errores con $args y JSON con 1 elemento.
$ErrorActionPreference = 'Continue'

# Trap global: si algo se rompe, muestra el error y NO cierra la ventana.
trap {
    Write-Host ''
    Write-Host '  +==============================================+' -ForegroundColor Red
    Write-Host '  |   ERROR INESPERADO                           |' -ForegroundColor Red
    Write-Host '  +==============================================+' -ForegroundColor Red
    Write-Host ''
    Write-Host ("  Mensaje  : {0}" -f $_.Exception.Message)            -ForegroundColor Yellow
    Write-Host ("  En línea : {0}" -f $_.InvocationInfo.ScriptLineNumber) -ForegroundColor DarkGray
    Write-Host ("  Comando  : {0}" -f $_.InvocationInfo.Line.Trim())   -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Stack trace:' -ForegroundColor DarkGray
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    Write-Host ''
    Read-Host 'Presiona Enter para cerrar'
    exit 1
}

$BackupName = '_rename_undo.json'

# ==============================================================
#  RESOLVER LISTA DE PATHS
# ==============================================================

$rawPaths = New-Object System.Collections.Generic.List[string]

if ($PathList -and (Test-Path -LiteralPath $PathList)) {
    foreach ($line in Get-Content -LiteralPath $PathList -Encoding Default) {
        if ($line) {
            $t = $line.Trim()
            if ($t -ne '') { [void]$rawPaths.Add($t) }
        }
    }
}
elseif ($Path -and $Path.Length -gt 0) {
    foreach ($p in $Path) {
        if ($p) { [void]$rawPaths.Add([string]$p) }
    }
}
else {
    # Sin parámetros -> usar directorio actual
    [void]$rawPaths.Add((Get-Location).Path)
}

# Resolver, validar y deduplicar
$pathsToProcess = New-Object System.Collections.Generic.List[string]
foreach ($p in $rawPaths) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Warning "Ruta no existe: $p"
        continue
    }
    if (Test-Path -LiteralPath $p -PathType Leaf) {
        $resolved = Split-Path $p -Parent
    } else {
        $resolved = $p.TrimEnd('\','/')
    }
    if ($resolved -and -not $pathsToProcess.Contains($resolved)) {
        [void]$pathsToProcess.Add($resolved)
    }
}

# ==============================================================
#  FUNCIONES DE RENOMBRADO
# ==============================================================

function Get-SeasonFromPath {
    param([string]$FullPath)
    if ($FullPath -match '[Ss]eason\s*0*(\d+)') { return [int]$Matches[1] }
    return $null
}

function Invoke-FixName {
    param([string]$Name, [string]$FullPath)

    $season = Get-SeasonFromPath $FullPath
    if ($null -eq $season) { $season = 1 }
    $out = $Name

    # P1 — Espaciado tras SxxExx
    $out = [regex]::Replace($out,
        '([Ss]\d{1,2}[Ee]\d{2,3})([^\s\.\]\[\(\)\-_])',
        '$1 $2')

    if ($out -match '[Ss]\d{1,2}[Ee]\d{2,3}') {
        if ($out -ne $Name) { return $out }
        return $null
    }

    # P2 — Estilo Gintama "S3 - 28"
    if ($out -match '^(.*?\b)S(\d{1,2})\s*[-–]\s*0*(\d{1,3})\b(.*)$') {
        $s = [int]$Matches[2]; $e = [int]$Matches[3]
        return '{0}S{1:00}E{2:00}{3}' -f $Matches[1], $s, $e, $Matches[4]
    }

    # P3 — Guion + número (espacios o underscores)
    if ($out -match '^(.*?[\s_][-–][\s_]+)0*(\d{1,3})((?:[\s_]|$).*)$') {
        $e = [int]$Matches[2]
        $rest = $Matches[3]
        if ($rest -ne '' -and $rest[0] -ne ' ' -and $rest[0] -ne '_') { $rest = ' ' + $rest }
        return '{0}S{1:00}E{2:00}{3}' -f $Matches[1], $season, $e, $rest
    }

    # P4 — Número sin guion (espacios o underscores)
    if ($out -match '^(.*[\s_])0*(\d{1,3})([\s_]+\[.*)$') {
        $e = [int]$Matches[2]
        if ($e -ge 1900 -and $e -le 2099) { return $null }
        return '{0}S{1:00}E{2:00}{3}' -f $Matches[1], $season, $e, $Matches[3]
    }

    return $null
}

# ==============================================================
#  RESTAURAR
# ==============================================================

function Invoke-Restore {
    param($BackupPaths)

    $totalOps = 0
    foreach ($bp in $BackupPaths) {
        $d = Get-Content -LiteralPath $bp -Encoding UTF8 -Raw | ConvertFrom-Json
        # Forzar array — si solo hay 1 elemento ConvertFrom-Json devuelve objeto suelto
        $opsArr = @($d.ops)
        $totalOps += $opsArr.Count
    }

    Write-Host ''
    Write-Host '  +----------------------------------------------+' -ForegroundColor Yellow
    Write-Host '  |   BACKUPS DETECTADOS                         |' -ForegroundColor Yellow
    Write-Host '  +----------------------------------------------+' -ForegroundColor Yellow
    Write-Host ("  Carpetas con backup : {0}"    -f @($BackupPaths).Count) -ForegroundColor White
    Write-Host ("  Cambios totales     : {0:N0}" -f $totalOps)             -ForegroundColor White
    foreach ($bp in $BackupPaths) {
        Write-Host ("    * {0}" -f (Split-Path $bp -Parent)) -ForegroundColor DarkGray
    }
    Write-Host ''
    $resp = Read-Host '  ¿Restaurar nombres originales? [S/N]'

    if ($resp -notmatch '^[Ss]') {
        Write-Host '  -> Continuando con renombrado normal (los backups serán sobrescritos)...' -ForegroundColor DarkGray
        Write-Host ''
        return $false
    }

    Write-Host ''
    $ok = 0; $err = 0; $skip = 0

    foreach ($bp in $BackupPaths) {
        $folderName = Split-Path (Split-Path $bp -Parent) -Leaf
        Write-Host ("-- Restaurando: {0}" -f $folderName) -ForegroundColor Cyan

        $data   = Get-Content -LiteralPath $bp -Encoding UTF8 -Raw | ConvertFrom-Json
        $opsArr = @($data.ops)
        $localErr = 0

        foreach ($op in $opsArr) {
            $dir         = Split-Path $op.OriginalPath -Parent
            $renamedPath = Join-Path $dir $op.NewName

            if (-not (Test-Path -LiteralPath $renamedPath)) {
                Write-Host ("  SKIP  {0}" -f $op.NewName) -ForegroundColor DarkGray
                $skip++; continue
            }
            try {
                Rename-Item -LiteralPath $renamedPath -NewName $op.OriginalName -ErrorAction Stop
                Write-Host ("  OK    {0}" -f $op.NewName)      -ForegroundColor Green
                Write-Host ("     ->  {0}" -f $op.OriginalName) -ForegroundColor DarkGreen
                $ok++
            } catch {
                Write-Host ("  ERR   {0}" -f $op.NewName)          -ForegroundColor Red
                Write-Host ("        {0}" -f $_.Exception.Message)  -ForegroundColor DarkRed
                $err++; $localErr++
            }
        }

        if ($localErr -eq 0) {
            Remove-Item -LiteralPath $bp -Force
            Write-Host '  -> Backup eliminado.' -ForegroundColor DarkGray
        } else {
            Write-Host '  -> Backup conservado (hubo errores).' -ForegroundColor DarkYellow
        }
        Write-Host ''
    }

    Write-Host '  ---------------------------------------------' -ForegroundColor DarkGray
    Write-Host ("  Restaurados : {0,5:N0}" -f $ok)   -ForegroundColor Green
    Write-Host ("  Errores     : {0,5:N0}" -f $err)  -ForegroundColor Red
    Write-Host ("  No hallados : {0,5:N0}" -f $skip) -ForegroundColor DarkGray
    Write-Host ''
    return $true
}

# ==============================================================
#  PUNTO DE ENTRADA
# ==============================================================

Write-Host ''
Write-Host '  +----------------------------------------------+' -ForegroundColor DarkCyan
Write-Host '  |   Rename-AnimeJellyfin                       |' -ForegroundColor DarkCyan
Write-Host '  +----------------------------------------------+' -ForegroundColor DarkCyan
Write-Host ("  Carpetas seleccionadas: {0}" -f $pathsToProcess.Count) -ForegroundColor White
foreach ($p in $pathsToProcess) {
    Write-Host ("    * {0}" -f $p) -ForegroundColor DarkGray
}
Write-Host ''

if ($pathsToProcess.Count -eq 0) {
    Write-Host '  ERROR: No hay rutas válidas para procesar.' -ForegroundColor Red
    Read-Host 'Presiona Enter para cerrar'
    exit 1
}

# Detectar backups previos en las carpetas seleccionadas
$backupsFound = New-Object System.Collections.Generic.List[string]
foreach ($p in $pathsToProcess) {
    $bp = Join-Path $p $BackupName
    if (Test-Path -LiteralPath $bp) { [void]$backupsFound.Add($bp) }
}

if ($backupsFound.Count -gt 0) {
    $restored = Invoke-Restore -BackupPaths $backupsFound
    if ($restored) {
        Read-Host 'Presiona Enter para cerrar'
        exit 0
    }
}

# ==============================================================
#  ESCANEO Y RENOMBRADO
# ==============================================================

$includeFilter = @($Extensions | ForEach-Object { "*.$_" })
$totalOk = 0; $totalSkip = 0; $totalErr = 0

foreach ($currentPath in $pathsToProcess) {

    Write-Host ("-- {0}" -f $currentPath) -ForegroundColor Cyan
    Write-Host ''

    $files = @(Get-ChildItem -LiteralPath $currentPath -Recurse -Include $includeFilter -File -ErrorAction SilentlyContinue)
    Write-Host ("  {0:N0} archivos encontrados" -f $files.Count) -ForegroundColor DarkGray
    Write-Host ''

    $folderOps = New-Object System.Collections.Generic.List[object]

    foreach ($file in $files) {
        $nameNoExt = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $ext       = [IO.Path]::GetExtension($file.Name)
        $newBase   = Invoke-FixName -Name $nameNoExt -FullPath $file.FullName

        if ($null -eq $newBase) { $totalSkip++; continue }

        $newName = $newBase + $ext

        $opObj = [pscustomobject]@{
            OriginalPath = $file.FullName
            OriginalName = $file.Name
            NewName      = $newName
        }

        try {
            Rename-Item -LiteralPath $file.FullName -NewName $newName -ErrorAction Stop
            Write-Host ("  OK    {0}" -f $file.Name) -ForegroundColor Green
            Write-Host ("     ->  {0}" -f $newName)   -ForegroundColor DarkGreen
            [void]$folderOps.Add($opObj)
            $totalOk++
        } catch {
            Write-Host ("  ERR   {0}" -f $file.Name)          -ForegroundColor Red
            Write-Host ("        {0}" -f $_.Exception.Message) -ForegroundColor DarkRed
            $totalErr++
        }
    }

    # Guardar backup en esta carpeta si hubo cambios
    if ($folderOps.Count -gt 0) {
        $backupPath = Join-Path $currentPath $BackupName
        $payload = [pscustomobject]@{
            timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            path      = $currentPath
            ops       = $folderOps.ToArray()
        }
        $payload | ConvertTo-Json -Depth 4 | Out-File -FilePath $backupPath -Encoding UTF8
        Write-Host ("  -> Backup: {0}" -f $backupPath) -ForegroundColor DarkGray
    }
    Write-Host ''
}

Write-Host '  =============================================' -ForegroundColor DarkGray
Write-Host ("  Carpetas procesadas : {0,3}"    -f $pathsToProcess.Count) -ForegroundColor White
Write-Host ("  Renombrados         : {0,5:N0}" -f $totalOk)              -ForegroundColor Green
Write-Host ("  Errores             : {0,5:N0}" -f $totalErr)             -ForegroundColor Red
Write-Host ("  Sin cambio          : {0,5:N0}" -f $totalSkip)            -ForegroundColor DarkGray
Write-Host ''
Read-Host 'Presiona Enter para cerrar'
