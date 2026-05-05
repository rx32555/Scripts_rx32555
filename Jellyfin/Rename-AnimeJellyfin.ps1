<#
.SYNOPSIS
    Renombra archivos de anime al formato Jellyfin (SxxExx).
    Genera un backup JSON para poder deshacer. Si detecta un backup previo,
    pregunta si restaurar antes de continuar.

.PARAMETER Path
    Ruta raíz a escanear (recursivo). Por defecto: directorio actual.

.PARAMETER Extensions
    Extensiones a procesar. Por defecto: mkv, mp4, avi.

.EXAMPLE
    .\Rename-AnimeJellyfin.ps1 -Path "H:\Anime3"
    .\Rename-AnimeJellyfin.ps1 -Path "J:\ANIME"
    .\Rename-AnimeJellyfin.ps1   # escanea el directorio actual
#>

param(
    [string]   $Path       = $PWD,
    [string[]] $Extensions = @('mkv','mp4','avi')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Backup guardado junto al script
$BackupFile = Join-Path $PSScriptRoot '_rename_undo.json'

# ══════════════════════════════════════════════════════════════
#  FUNCIONES DE RENOMBRADO
# ══════════════════════════════════════════════════════════════

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

    # ── P1: Espaciado incorrecto tras SxxExx ──────────────────────────────
    # "S01E01texto" → "S01E01 texto"
    $out = [regex]::Replace(
        $out,
        '([Ss]\d{1,2}[Ee]\d{2,3})([^\s\.\]\[\(\)\-_])',
        '$1 $2'
    )

    # Ya tiene SxxExx (bien formado) → devolver solo si P1 hizo cambio
    if ($out -match '[Ss]\d{1,2}[Ee]\d{2,3}') {
        if ($out -ne $Name) { return $out }
        return $null
    }

    # ── P2: Estilo Gintama "S3 - 28" → "S03E28" ──────────────────────────
    if ($out -match '^(.*?\b)S(\d{1,2})\s*[-–]\s*0*(\d{1,3})\b(.*)$') {
        $s = [int]$Matches[2]; $e = [int]$Matches[3]
        return '{0}S{1:00}E{2:00}{3}' -f $Matches[1], $s, $e, $Matches[4]
    }

    # ── P3: Guion con número suelto "- 05 [" o "- 05 v1.1" ───────────────
    if ($out -match '^(.*?\s[-–]\s+)0*(\d{1,3})((?:\s|$).*)$') {
        $e    = [int]$Matches[2]
        $rest = $Matches[3]
        if ($rest -ne '' -and $rest[0] -ne ' ') { $rest = ' ' + $rest }
        return '{0}S{1:00}E{2:00}{3}' -f $Matches[1], $season, $e, $rest
    }

    # ── P4: Número suelto sin guion "ShowName 01 [720p]" ─────────────────
    if ($out -match '^(.*\s)0*(\d{1,3})(\s+\[.*)$') {
        $e = [int]$Matches[2]
        if ($e -ge 1900 -and $e -le 2099) { return $null }   # ignorar años
        return '{0}S{1:00}E{2:00}{3}' -f $Matches[1], $season, $e, $Matches[3]
    }

    return $null
}

# ══════════════════════════════════════════════════════════════
#  RESTAURAR desde backup
# ══════════════════════════════════════════════════════════════

function Invoke-Restore {
    param([string]$BackupPath)

    $data    = Get-Content -LiteralPath $BackupPath -Encoding UTF8 | ConvertFrom-Json
    $total   = $data.ops.Count
    $date    = $data.timestamp
    $srcPath = $data.path

    Write-Host ''
    Write-Host '  ┌──────────────────────────────────────────────┐' -ForegroundColor Yellow
    Write-Host '  │   BACKUP DETECTADO                           │' -ForegroundColor Yellow
    Write-Host '  └──────────────────────────────────────────────┘' -ForegroundColor Yellow
    Write-Host ("  Fecha    : {0}"   -f $date)    -ForegroundColor White
    Write-Host ("  Ruta     : {0}"   -f $srcPath) -ForegroundColor White
    Write-Host ("  Cambios  : {0:N0}" -f $total)  -ForegroundColor White
    Write-Host ''
    $resp = Read-Host '  ¿Restaurar nombres originales? [S/N]'

    if ($resp -notmatch '^[Ss]') {
        Write-Host '  → Continuando con renombrado normal...' -ForegroundColor DarkGray
        Write-Host ''
        return $false
    }

    Write-Host ''
    $ok = 0; $err = 0; $skip = 0

    foreach ($op in $data.ops) {
        # El archivo renombrado está en: directorio original + nombre nuevo
        $dir         = Split-Path $op.OriginalPath -Parent
        $renamedPath = Join-Path $dir $op.NewName

        if (-not (Test-Path -LiteralPath $renamedPath)) {
            Write-Host ("  SKIP  {0}" -f $op.NewName) -ForegroundColor DarkGray
            $skip++
            continue
        }
        try {
            Rename-Item -LiteralPath $renamedPath -NewName $op.OriginalName -ErrorAction Stop
            Write-Host ("  OK    {0}" -f $op.NewName)      -ForegroundColor Green
            Write-Host ("     →  {0}" -f $op.OriginalName) -ForegroundColor DarkGreen
            $ok++
        }
        catch {
            Write-Host ("  ERR   {0}" -f $op.NewName)       -ForegroundColor Red
            Write-Host ("        {0}" -f $_.Exception.Message) -ForegroundColor DarkRed
            $err++
        }
    }

    # Borrar backup si todo OK
    if ($err -eq 0) {
        Remove-Item -LiteralPath $BackupPath -Force
        Write-Host ''
        Write-Host '  Backup eliminado (restauración completa).' -ForegroundColor DarkGray
    } else {
        Write-Host ''
        Write-Host '  Backup conservado (hubo errores en la restauración).' -ForegroundColor DarkYellow
    }

    Write-Host ''
    Write-Host '  ─────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host ("  Restaurados : {0,5:N0}" -f $ok)   -ForegroundColor Green
    Write-Host ("  Errores     : {0,5:N0}" -f $err)  -ForegroundColor Red
    Write-Host ("  No hallados : {0,5:N0}" -f $skip) -ForegroundColor DarkGray
    Write-Host ''

    return $true
}

# ══════════════════════════════════════════════════════════════
#  PUNTO DE ENTRADA
# ══════════════════════════════════════════════════════════════

Write-Host ''
Write-Host '  ┌──────────────────────────────────────────────┐' -ForegroundColor DarkCyan
Write-Host '  │   Rename-AnimeJellyfin (genérico)            │' -ForegroundColor DarkCyan
Write-Host '  └──────────────────────────────────────────────┘' -ForegroundColor DarkCyan
Write-Host ("  Ruta : {0}" -f $Path) -ForegroundColor White
Write-Host ''

# ── Verificar ruta ────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "La ruta '$Path' no existe."
    exit 1
}

# ── Comprobar backup previo ───────────────────────────────────
if (Test-Path -LiteralPath $BackupFile) {
    $restored = Invoke-Restore -BackupPath $BackupFile
    if ($restored) { exit 0 }
}

# ══════════════════════════════════════════════════════════════
#  RENOMBRADO
# ══════════════════════════════════════════════════════════════

$includeFilter = $Extensions | ForEach-Object { "*.$_" }
$files = Get-ChildItem -LiteralPath $Path -Recurse -Include $includeFilter -File
Write-Host ("  {0:N0} archivos encontrados`n" -f $files.Count) -ForegroundColor DarkGray

$ops   = [System.Collections.Generic.List[object]]::new()
$ok    = 0
$skip  = 0
$err   = 0

foreach ($file in $files) {

    $nameNoExt = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    $ext       = [IO.Path]::GetExtension($file.Name)

    $newBase = Invoke-FixName -Name $nameNoExt -FullPath $file.FullName

    if ($null -eq $newBase) {
        $skip++
        continue
    }

    $newName = $newBase + $ext

    # Guardar en lista de backup ANTES de renombrar
    $ops.Add([pscustomobject]@{
        OriginalPath = $file.FullName
        OriginalName = $file.Name
        NewName      = $newName
    })

    try {
        Rename-Item -LiteralPath $file.FullName -NewName $newName -ErrorAction Stop
        Write-Host ("  OK    {0}" -f $file.Name) -ForegroundColor Green
        Write-Host ("     →  {0}" -f $newName)   -ForegroundColor DarkGreen
        $ok++
    }
    catch {
        Write-Host ("  ERR   {0}" -f $file.Name)          -ForegroundColor Red
        Write-Host ("        {0}" -f $_.Exception.Message) -ForegroundColor DarkRed
        # Quitar de la lista de backup (no se renombró)
        $ops.RemoveAt($ops.Count - 1)
        $err++
    }
}

# ── Guardar backup ────────────────────────────────────────────
if ($ops.Count -gt 0) {
    $backup = [pscustomobject]@{
        timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        path      = $Path
        ops       = $ops
    }
    $backup | ConvertTo-Json -Depth 4 | Out-File -FilePath $BackupFile -Encoding UTF8
    Write-Host ''
    Write-Host ("  Backup guardado : {0}" -f $BackupFile) -ForegroundColor DarkGray
    Write-Host   "  (Ejecuta el script de nuevo para ver la opción de restaurar)" `
        -ForegroundColor DarkGray
}

# ── Resumen ───────────────────────────────────────────────────
Write-Host ''
Write-Host '  ─────────────────────────────────────────────' -ForegroundColor DarkGray
Write-Host ("  Renombrados : {0,5:N0}" -f $ok)   -ForegroundColor Green
Write-Host ("  Errores     : {0,5:N0}" -f $err)  -ForegroundColor Red
Write-Host ("  Sin cambio  : {0,5:N0}" -f $skip) -ForegroundColor DarkGray
Write-Host ''
