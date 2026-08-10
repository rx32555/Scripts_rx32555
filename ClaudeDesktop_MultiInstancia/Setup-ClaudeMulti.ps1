<#
.SYNOPSIS
    Configura Claude Desktop para correr tres (o mas) instancias aisladas en el mismo PC,
    cada una con su propia cuenta, sesion, MCPs y configuracion.

.DESCRIPTION
    Claude Desktop es una app Electron. Electron guarda TODO el estado de usuario
    (token de sesion, configuracion, MCPs, cache) en una carpeta "user data".
    Si se lanza el ejecutable con --user-data-dir="ruta", esa instancia usa una
    carpeta distinta y por lo tanto es una sesion completamente independiente.

    Este script:
      1. Detecta donde esta instalado Claude Desktop.
      2. Si la instalacion es MSIX (Microsoft Store / WindowsApps), hace una copia
         portable a una carpeta normal, porque Windows bloquea ejecutar el .exe
         desde WindowsApps con parametros.
      3. Crea un acceso directo por perfil en el Escritorio.

    En instalaciones MSIX el PRIMER perfil se lanza a traves del paquete de la
    Store (no de la copia portable), asi conserva las auto-actualizaciones.

.PARAMETER Profiles
    Nombres de los perfiles. El PRIMERO usa la carpeta de datos por defecto
    (%APPDATA%\Claude), asi conservas la sesion y los MCPs que ya tienes.
    Los siguientes usan %APPDATA%\Claude-<Nombre>.

.PARAMETER PortableDir
    Carpeta destino de la copia portable (solo se usa en instalaciones MSIX).

.PARAMETER CopyMcpConfig
    Copia el nodo mcpServers de claude_desktop_config.json del perfil por defecto
    a cada perfil nuevo. Solo esa clave: no copia sesion, credenciales ni las
    preferencias de UI ligadas a tu cuenta que viven en el mismo archivo.

.PARAMETER NoLauncher
    Los accesos directos apuntan directo al .exe, sin pasar por el lanzador que
    comprueba actualizaciones. Los iconos de color se siguen aplicando.

.PARAMETER GrantWindowsAppsRead
    Autoriza sin preguntar el takeown+icacls sobre la carpeta del paquete MSIX,
    para escenarios desatendidos. Solo se usa si la copia falla por permisos.

.PARAMETER Revert
    Deshace la configuracion: borra los accesos directos, las carpetas de datos
    de los perfiles extra y la copia portable. Nunca toca %APPDATA%\Claude.

.PARAMETER Force
    Rehace la copia portable si ya existe, sobrescribe la config MCP ya copiada
    y, con -Revert, borra sin pedir confirmacion.

.EXAMPLE
    .\Setup-ClaudeMulti.ps1

.EXAMPLE
    .\Setup-ClaudeMulti.ps1 -Profiles 'Personal','Trabajo','Cliente' -CopyMcpConfig

.EXAMPLE
    .\Setup-ClaudeMulti.ps1 -Profiles 'Personal','Trabajo','Cliente' -Revert
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string[]]$Profiles    = @('Cuenta1', 'Cuenta2', 'Cuenta3'),
    [string]  $PortableDir = 'C:\ClaudePortable',
    [switch]  $CopyMcpConfig,
    [switch]  $NoLauncher,
    [switch]  $GrantWindowsAppsRead,
    [switch]  $Revert,
    [switch]  $Force,
    [string]  $Language    = $null
)

$ErrorActionPreference = 'Stop'

# --- Idioma e Internacionalizacion (i18n) -------------------------------------
$script:Lang = 'en'
if (-not [string]::IsNullOrWhiteSpace($Language)) {
    if ($Language -match '^es') { $script:Lang = 'es' }
    else { $script:Lang = 'en' }
}
else {
    try {
        $uiCulture = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
        if ($uiCulture -eq 'es') { $script:Lang = 'es' }
    } catch {
        $script:Lang = 'en'
    }
}

$script:I18n = @{
    es = @{
        HeaderTitle          = 'Claude Desktop - configuracion de multiples instancias'
        MenuTitle            = 'Claude Desktop - Multi Instancia (Menu)'
        CurrentInstances     = 'Instancias configuradas actualmente'
        CopyMcpsLabel        = 'Copiar MCPs (-CopyMcpConfig)'
        MenuOpt1             = 'Ejecutar / Actualizar instalacion actual ({0})'
        MenuOpt2             = 'Especificar cantidad total de instancias (ej: 4 -> Cuenta1..Cuenta4)'
        MenuOpt3             = 'Anadir una nueva instancia / perfil (ej: "Cuenta4" o "Trabajo")'
        MenuOpt4             = 'Alternar copia de MCPs a nuevos perfiles'
        MenuOpt5             = 'Revertir / Eliminar perfiles'
        MenuOpt6             = 'Salir'
        SelectOpt            = 'Selecciona una opcion (1-6)'
        EnterTotalNum        = 'Ingresa el numero total de instancias deseado (ej: 4)'
        InvalidNum           = 'Numero no valido.'
        EnterNewName         = 'Ingresa el nombre del nuevo perfil o instancia (ej: Cuenta4 o Trabajo)'
        ProfileExists        = 'El perfil "{0}" ya existe.'
        NameCannotBeEmpty    = 'El nombre no puede estar vacio.'
        CopyMcpsActive       = 'Copia de MCPs: ACTIVADA'
        CopyMcpsInactive     = 'Copia de MCPs: DESACTIVADA'
        WarnDeleteData       = 'Se eliminaran accesos directos y datos de perfiles extra.'
        ConfirmRevert        = 'Confirmas revertir la configuracion? (S/N)'
        OpCancelled          = 'Operacion cancelada.'
        InvalidOpt           = 'Opcion invalida.'
        SearchingInstall     = 'Buscando la instalacion de Claude Desktop...'
        NotFound             = 'No se encontro Claude Desktop en este equipo.'
        InstallMode          = 'Modo de instalacion: {0}'
        FolderLabel          = 'Carpeta: {0}'
        InstalledVer         = 'Version instalada: {0}'
        MsixDetected         = 'Instalacion tipo MSIX detectada (Microsoft Store).'
        MsixNote             = 'Windows no permite lanzar el .exe desde WindowsApps con parametros, asi que hay que hacer una copia portable en una carpeta normal.'
        PortableUpToDate     = 'Copia portable al dia (version {0}). No hay nada que actualizar.'
        GeneratingIcons      = 'Generando iconos de color por perfil...'
        InstallingLauncher   = 'Instalando lanzador (comprueba actualizaciones antes de abrir)...'
        CreatingShortcuts    = 'Creando accesos directos en el Escritorio...'
        ShortcutExists       = 'Ya existia "{0}.lnk" en el Escritorio: se sobrescribe.'
        ProfileLabelOriginal = 'Claude - {0} (perfil actual)'
        ProfileLabelExtra    = 'Claude - {0}'
        ReadyTitle           = 'Listo'
        HeaderPerfil         = 'Perfil'
        HeaderColor          = 'Color'
        HeaderLanza          = 'Lanza'
        HeaderAcceso         = 'Acceso'
        HowToUse             = 'Como usarlo:'
        UseFirstLnk          = 'Abre el primer acceso directo -> es tu sesion de siempre.'
        UseOtherLnks         = 'Abre los accesos directos de las otras cuentas -> pediran login. Entra con cada cuenta.'
        AllWindowsOpen       = 'Las ventanas pueden estar abiertas al mismo tiempo.'
        BadgeNote            = 'Cada acceso directo lleva una insignia de color con su inicial.'
        UpdateCheckNote      = 'Al abrir un perfil se comprueba si Claude tiene version nueva y la actualiza.'
        ImportantTitle       = 'ImportantTitle'
        CoworkNote           = 'Cowork corre en una VM Hyper-V unica por maquina: solo una instancia puede usar Cowork a la vez.'
        NoMcpNote            = 'Los perfiles nuevos arrancan SIN MCP servers. Usa -CopyMcpConfig para copiar los del perfil por defecto.'
        StoreNote            = 'El primer perfil se lanza por el paquete de la Store: se actualiza solo.'
        RevertCmdNote        = 'Para revertir: vuelve a correr este script con -Revert.'
    }
    en = @{
        HeaderTitle          = 'Claude Desktop - Multi-Instance Setup'
        MenuTitle            = 'Claude Desktop - Multi-Instance (Menu)'
        CurrentInstances     = 'Currently configured instances'
        CopyMcpsLabel        = 'Copy MCPs (-CopyMcpConfig)'
        MenuOpt1             = 'Run / Update current installation ({0})'
        MenuOpt2             = 'Specify total number of instances (e.g. 4 -> Cuenta1..Cuenta4)'
        MenuOpt3             = 'Add a new instance / profile (e.g. "Cuenta4" or "Work")'
        MenuOpt4             = 'Toggle copying MCPs to new profiles'
        MenuOpt5             = 'Revert / Delete profiles'
        MenuOpt6             = 'Exit'
        SelectOpt            = 'Select an option (1-6)'
        EnterTotalNum        = 'Enter desired total number of instances (e.g. 4)'
        InvalidNum           = 'Invalid number.'
        EnterNewName         = 'Enter name for the new profile or instance (e.g. Cuenta4 or Work)'
        ProfileExists        = 'Profile "{0}" already exists.'
        NameCannotBeEmpty    = 'Name cannot be empty.'
        CopyMcpsActive       = 'Copy MCPs: ENABLED'
        CopyMcpsInactive     = 'Copy MCPs: DISABLED'
        WarnDeleteData       = 'Shortcuts and extra profile data will be deleted.'
        ConfirmRevert        = 'Are you sure you want to revert configuration? (Y/N)'
        OpCancelled          = 'Operation cancelled.'
        InvalidOpt           = 'Invalid option.'
        SearchingInstall     = 'Searching for Claude Desktop installation...'
        NotFound             = 'Claude Desktop was not found on this computer.'
        InstallMode          = 'Installation mode: {0}'
        FolderLabel          = 'Folder: {0}'
        InstalledVer         = 'Installed version: {0}'
        MsixDetected         = 'MSIX installation detected (Microsoft Store).'
        MsixNote             = 'Windows does not allow launching the .exe from WindowsApps with parameters, so a portable copy is made to a normal folder.'
        PortableUpToDate     = 'Portable copy up to date (version {0}). Nothing to update.'
        GeneratingIcons      = 'Generating colored icons per profile...'
        InstallingLauncher   = 'Installing launcher (checks for updates before opening)...'
        CreatingShortcuts    = 'Creating desktop shortcuts...'
        ShortcutExists       = '"{0}.lnk" already exists on Desktop: overwriting.'
        ProfileLabelOriginal = 'Claude - {0} (current profile)'
        ProfileLabelExtra    = 'Claude - {0}'
        ReadyTitle           = 'Ready'
        HeaderPerfil         = 'Profile'
        HeaderColor          = 'Color'
        HeaderLanza          = 'Launcher'
        HeaderAcceso         = 'Shortcut'
        HowToUse             = 'How to use it:'
        UseFirstLnk          = 'Open the first shortcut -> this is your usual session.'
        UseOtherLnks         = 'Open shortcuts for other accounts -> they will prompt for login.'
        AllWindowsOpen       = 'All windows can be open at the same time.'
        BadgeNote            = 'Each shortcut has a colored badge with its initial.'
        UpdateCheckNote      = 'Opening a profile checks if Claude has a new version and updates it.'
        ImportantTitle       = 'Important:'
        CoworkNote           = 'Cowork runs in a single Hyper-V VM per machine: only one instance can use Cowork at a time.'
        NoMcpNote            = 'New profiles start WITHOUT MCP servers. Use -CopyMcpConfig to copy them from default profile.'
        StoreNote            = 'The first profile launches via the Store package: updates automatically.'
        RevertCmdNote        = 'To revert: run this script again with -Revert.'
    }
}

function Get-I18nStr {
    param(
        [Parameter(Mandatory)][string]$Key,
        [object[]]$Args
    )
    $lang = $script:Lang
    if (-not $script:I18n.ContainsKey($lang)) { $lang = 'en' }
    $str = $script:I18n[$lang][$Key]
    if (-not $str) { $str = $script:I18n['en'][$Key] }
    if ($Args -and $Args.Count -gt 0) { return ($str -f $Args) }
    return $str
}

# ---------------------------------------------------------------- helpers ---

function Write-Step { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "    [ok]   $m" -ForegroundColor Green }
function Write-Note { param([string]$m) Write-Host "    ->     $m" -ForegroundColor Gray }
function Write-Warn { param([string]$m) Write-Host "    [!]    $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "    [X]    $m" -ForegroundColor Red }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Convierte "1.10.0", "app-1.9.0-beta", "1.26832.0.0" a [version] comparable.
# Evita el orden lexicografico, que pone 1.9.0 por encima de 1.10.0.
function ConvertTo-SafeVersion {
    param([string]$Text)

    $zero  = [version]'0.0.0.0'
    if ([string]::IsNullOrWhiteSpace($Text)) { return $zero }

    $clean = ($Text -replace '^[^0-9]*', '') -replace '[^0-9\.].*$', ''
    $clean = $clean.Trim('.')
    if ([string]::IsNullOrWhiteSpace($clean) -or $clean -notmatch '\.') { $clean = "$clean.0" }

    $parsed = $zero
    if ([version]::TryParse($clean, [ref]$parsed)) { return $parsed }
    return $zero
}

# --- Iconos de color por perfil ---------------------------------------------
# Se toma el icono real de Claude y se le pega una insignia de color con la
# inicial del perfil, para distinguir los accesos directos de un vistazo.

$script:HomeDir = Join-Path $env:APPDATA 'ClaudeMulti'

# Ojo: nada de coral/naranja. El icono de Claude ya es coral y la insignia
# se volveria invisible sobre el.
$script:Palette = @(
    @{ Nombre = 'azul';   Rgb = @( 37, 118, 208) },
    @{ Nombre = 'verde';  Rgb = @( 34, 150,  94) },
    @{ Nombre = 'morado'; Rgb = @(126,  78, 214) },
    @{ Nombre = 'cian';   Rgb = @( 20, 150, 176) },
    @{ Nombre = 'rosa';   Rgb = @(209,  56, 130) },
    @{ Nombre = 'azabache'; Rgb = @( 45,  55,  72) },
    @{ Nombre = 'oliva';  Rgb = @(107, 142,  35) }
)

function Get-ProfileColor {
    param([int]$Index)
    $script:Palette[$Index % $script:Palette.Count]
}

function Initialize-IconApi {
    if (-not ('ClaudeMulti.IconApi' -as [type])) {
        Add-Type -Namespace 'ClaudeMulti' -Name 'IconApi' -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern int PrivateExtractIcons(string lpszFile, int nIconIndex,
    int cxDesired, int cyDesired, IntPtr[] phicon, int[] piconid, int nIcons, int flags);
[DllImport("user32.dll")]
public static extern bool DestroyIcon(IntPtr hIcon);
'@
    }
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
}

# Extrae el icono grande del .exe (256px). Devuelve $null si no se puede.
function Get-AppIconBitmap {
    param([Parameter(Mandatory)][string]$ExePath, [int]$Size = 256)

    $handles = New-Object IntPtr[] 1
    $ids     = New-Object int[] 1
    $bmp     = $null
    try {
        $n = [ClaudeMulti.IconApi]::PrivateExtractIcons($ExePath, 0, $Size, $Size, $handles, $ids, 1, 0)
        if ($n -gt 0 -and $handles[0] -ne [IntPtr]::Zero) {
            $ico = [System.Drawing.Icon]::FromHandle($handles[0])
            $bmp = New-Object System.Drawing.Bitmap($Size, $Size,
                     [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = 'HighQualityBicubic'
            $g.DrawIcon($ico, (New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)))
            $g.Dispose()
            $ico.Dispose()
        }
    }
    catch { $bmp = $null }
    finally {
        if ($handles[0] -ne [IntPtr]::Zero) { [void][ClaudeMulti.IconApi]::DestroyIcon($handles[0]) }
    }
    return $bmp
}

function New-BadgedBitmap {
    param(
        [System.Drawing.Bitmap]$Base,
        [Parameter(Mandatory)][string]$Letter,
        [Parameter(Mandatory)][int[]]$Rgb,
        [Parameter(Mandatory)][int]$Size
    )

    $color = [System.Drawing.Color]::FromArgb(255, $Rgb[0], $Rgb[1], $Rgb[2])
    $bmp   = New-Object System.Drawing.Bitmap($Size, $Size,
               [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g     = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode   = 'HighQuality'
    $g.TextRenderingHint = 'AntiAliasGridFit'

    if ($Base) {
        $g.DrawImage($Base, (New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)))
    }
    else {
        # Sin icono de origen: cuadrado redondeado del color del perfil.
        $pad  = [int]($Size * 0.06)
        $r    = [int]($Size * 0.22)
        $rect = New-Object System.Drawing.Rectangle($pad, $pad, ($Size - 2 * $pad), ($Size - 2 * $pad))
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc($rect.X, $rect.Y, $r, $r, 180, 90)
        $path.AddArc(($rect.Right - $r), $rect.Y, $r, $r, 270, 90)
        $path.AddArc(($rect.Right - $r), ($rect.Bottom - $r), $r, $r, 0, 90)
        $path.AddArc($rect.X, ($rect.Bottom - $r), $r, $r, 90, 90)
        $path.CloseFigure()
        $fill = New-Object System.Drawing.SolidBrush($color)
        $g.FillPath($fill, $path)
        $fill.Dispose(); $path.Dispose()
    }

    # Insignia circular abajo a la derecha. Grande a proposito: a 32px es lo
    # unico que distingue un acceso directo de otro.
    $d    = [int]($Size * 0.54)
    $x    = $Size - $d
    $y    = $Size - $d
    $ring = [Math]::Max(1, [int]($Size * 0.03))

    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.FillEllipse($white, ($x - $ring), ($y - $ring), ($d + 2 * $ring), ($d + 2 * $ring))
    $brush = New-Object System.Drawing.SolidBrush($color)
    $g.FillEllipse($brush, $x, $y, $d, $d)

    # La letra solo se lee a partir de cierto tamano.
    if ($Size -ge 48) {
        $fontSize = [single]($d * 0.60)
        $font = New-Object System.Drawing.Font('Segoe UI', $fontSize,
                  [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment     = 'Center'
        $fmt.LineAlignment = 'Center'
        $box = New-Object System.Drawing.RectangleF($x, $y, $d, $d)
        $g.DrawString($Letter.ToUpperInvariant(), $font, $white, $box, $fmt)
        $font.Dispose(); $fmt.Dispose()
    }

    $white.Dispose(); $brush.Dispose(); $g.Dispose()
    return $bmp
}

# Escribe un .ico multi-resolucion con frames PNG (soportado desde Vista).
function Save-IcoFile {
    param(
        [Parameter(Mandatory)][System.Drawing.Bitmap[]]$Bitmaps,
        [Parameter(Mandatory)][string]$Path
    )

    $pngs = @()
    foreach ($b in $Bitmaps) {
        $ms = New-Object IO.MemoryStream
        $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngs += , $ms.ToArray()
        $ms.Dispose()
    }

    $fs = [IO.File]::Open($Path, [IO.FileMode]::Create)
    $bw = New-Object IO.BinaryWriter($fs)
    try {
        $bw.Write([uint16]0)             # reservado
        $bw.Write([uint16]1)             # tipo: 1 = icono
        $bw.Write([uint16]$pngs.Count)

        $offset = 6 + (16 * $pngs.Count)
        for ($i = 0; $i -lt $pngs.Count; $i++) {
            $w = $Bitmaps[$i].Width
            $dim = [byte]$(if ($w -ge 256) { 0 } else { $w })   # 0 significa 256
            $bw.Write($dim)              # ancho
            $bw.Write($dim)              # alto
            $bw.Write([byte]0)           # colores de paleta
            $bw.Write([byte]0)           # reservado
            $bw.Write([uint16]1)         # planos
            $bw.Write([uint16]32)        # bits por pixel
            $bw.Write([uint32]$pngs[$i].Length)
            $bw.Write([uint32]$offset)
            $offset += $pngs[$i].Length
        }
        foreach ($p in $pngs) { $bw.Write($p) }
        $bw.Flush()
    }
    finally { $bw.Dispose(); $fs.Dispose() }
}

function New-ProfileIcon {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Index,
        [string]$SourceExe,
        [Parameter(Mandatory)][string]$OutDir
    )

    Initialize-IconApi
    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }

    $color  = Get-ProfileColor -Index $Index
    $letter = $Name.Substring(0, 1)
    $out    = Join-Path $OutDir "$Name.ico"

    $base = $null
    if ($SourceExe -and (Test-Path -LiteralPath $SourceExe)) {
        $base = Get-AppIconBitmap -ExePath $SourceExe -Size 256
    }

    $frames = @()
    foreach ($s in 256, 128, 64, 48, 32, 16) {
        $frames += New-BadgedBitmap -Base $base -Letter $letter -Rgb $color.Rgb -Size $s
    }
    Save-IcoFile -Bitmaps $frames -Path $out
    foreach ($f in $frames) { $f.Dispose() }
    if ($base) { $base.Dispose() }

    return [pscustomobject]@{ Path = $out; Color = $color.Nombre }
}

function Get-ExeVersion {
    param([string]$Path)
    try {
        $fi = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        if ($fi.FileVersion) { return $fi.FileVersion.Trim() }
    } catch { }
    return $null
}

# --- Sello de version de la copia portable -----------------------------------
# Se deja un archivo dentro de PortableDir con la version que se copio. En cada
# ejecucion se compara con la instalada; si cambia, la copia se rehace sola.

$script:StampFile = '.claude-multi.json'

function Get-PortableStamp {
    param([Parameter(Mandatory)][string]$PortablePath)

    $file = Join-Path $PortablePath $script:StampFile
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try {
        $s = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        if (-not $s.version -or -not $s.exe) { return $null }
        return $s
    }
    catch { return $null }
}

# Procesos corriendo desde la copia portable: bloquearian el borrado al actualizar.
function Get-PortableProcess {
    param([Parameter(Mandatory)][string]$PortablePath)

    $base = $PortablePath.TrimEnd('\') + '\'
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) }
        catch { $false }
    }
}

function Set-PortableStamp {
    param(
        [Parameter(Mandatory)][string]$PortablePath,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Exe,
        [string]$Source
    )
    $stamp = [pscustomobject]@{
        version = $Version
        exe     = $Exe
        source  = $Source
        stamped = (Get-Date).ToString('s')
    }
    $file = Join-Path $PortablePath $script:StampFile
    [IO.File]::WriteAllText($file, ($stamp | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}

# Valida nombres de perfil: se usan como nombre de archivo (.lnk) y de carpeta.
function Assert-ProfileNames {
    param([string[]]$Names)

    if (-not $Names -or $Names.Count -eq 0) {
        throw 'La lista de perfiles esta vacia.'
    }

    $bad = [IO.Path]::GetInvalidFileNameChars()
    foreach ($n in $Names) {
        if ([string]::IsNullOrWhiteSpace($n)) {
            throw 'Hay un nombre de perfil vacio en -Profiles.'
        }
        if ($n.IndexOfAny($bad) -ge 0) {
            throw "El nombre de perfil '$n' contiene caracteres no validos para un archivo o carpeta."
        }
        if ($n -ne $n.Trim() -or $n.EndsWith('.')) {
            throw "El nombre de perfil '$n' no puede empezar/terminar en espacio ni terminar en punto."
        }
    }

    $dupes = $Names | Group-Object -Property { $_.ToLowerInvariant() } |
             Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Group[0] }
    if ($dupes) {
        throw "Hay nombres de perfil repetidos: $($dupes -join ', ')"
    }

    if ($Names.Count -lt 2 -and -not $Revert) {
        Write-Warn 'Solo se indico un perfil: no se crea ninguna instancia adicional.'
    }
}

function Get-ClaudeInstall {
    # --- 1. Instalacion clasica (installer .exe, tipo Squirrel) --------------
    $bases = @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}) |
             Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $roots = @()
    foreach ($b in $bases) {
        $roots += (Join-Path $b 'AnthropicClaude')
        $roots += (Join-Path $b 'Claude')
    }
    $roots = $roots | Where-Object { Test-Path $_ } | Select-Object -Unique

    foreach ($root in $roots) {
        $direct = Join-Path $root 'claude.exe'
        if (Test-Path $direct) {
            return [pscustomobject]@{
                Exe = $direct; Dir = $root; Mode = 'Direct'; Aumid = $null
                Version = (Get-ExeVersion $direct)
            }
        }
        # Ordenar por version real, no por nombre: app-1.10.0 > app-1.9.0
        $appDirs = Get-ChildItem -LiteralPath $root -Directory -Filter 'app-*' `
                     -ErrorAction SilentlyContinue |
                   Sort-Object -Property @{ Expression = { ConvertTo-SafeVersion $_.Name } } -Descending
        foreach ($d in $appDirs) {
            $exe = Join-Path $d.FullName 'claude.exe'
            if (Test-Path $exe) {
                $v = Get-ExeVersion $exe
                if (-not $v) { $v = ($d.Name -replace '^app-', '') }
                return [pscustomobject]@{
                    Exe = $exe; Dir = $d.FullName; Mode = 'Direct'; Aumid = $null; Version = $v
                }
            }
        }
    }

    # --- 2. Instalacion MSIX (Microsoft Store) ------------------------------
    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        Write-Warn 'Get-AppxPackage no esta disponible en esta edicion de PowerShell.'
        Write-Note 'No se puede detectar una instalacion de Microsoft Store desde aqui.'
        Write-Note 'Vuelve a ejecutar con Windows PowerShell 5.1:'
        Write-Note '  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup-ClaudeMulti.ps1'
        return $null
    }

    $pkg = Get-AppxPackage -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -match 'Claude' -or $_.Publisher -match 'Anthropic' } |
           Sort-Object -Property @{ Expression = { ConvertTo-SafeVersion $_.Version } } -Descending |
           Select-Object -First 1

    if ($pkg -and $pkg.InstallLocation) {
        $aumid = $null
        try {
            $appId = (Get-AppxPackageManifest $pkg).Package.Applications.Application.Id |
                     Select-Object -First 1
            if ($appId) { $aumid = "$($pkg.PackageFamilyName)!$appId" }
        } catch { }

        $exe = Get-ChildItem -LiteralPath $pkg.InstallLocation -Filter 'claude.exe' `
                 -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1

        return [pscustomobject]@{
            Exe     = $(if ($exe) { $exe.FullName } else { $null })
            Dir     = $pkg.InstallLocation
            Mode    = 'Msix'
            Aumid   = $aumid
            Version = [string]$pkg.Version
        }
    }

    return $null
}

function New-ClaudeShortcut {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Target,
        [string]$Arguments   = '',
        [string]$IconPath,
        [string]$Description = 'Claude Desktop'
    )
    $desktop = [Environment]::GetFolderPath('Desktop')
    $path    = Join-Path $desktop "$Name.lnk"

    if (Test-Path -LiteralPath $path) {
        Write-Warn "Ya existia '$Name.lnk' en el Escritorio: se sobrescribe."
    }

    if (-not $PSCmdlet.ShouldProcess($path, 'Crear acceso directo')) { return $path }

    $shell = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $lnk   = $shell.CreateShortcut($path)
        $lnk.TargetPath       = $Target
        $lnk.WorkingDirectory = Split-Path -Parent $Target
        $lnk.Arguments        = $Arguments
        $lnk.Description      = $Description
        if ($IconPath) { $lnk.IconLocation = "$IconPath,0" }
        $lnk.Save()
    }
    finally {
        if ($shell) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
    }
    return $path
}

function Copy-ToPortable {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [switch]$Overwrite
    )

    if ((Test-Path $Destination) -and -not $Overwrite) {
        Write-Note 'Se reutilizara la copia existente.'
        return
    }
    if (Test-Path $Destination) {
        if ($PSCmdlet.ShouldProcess($Destination, 'Borrar copia portable anterior')) {
            Write-Note 'Borrando copia anterior...'
            Remove-Item -LiteralPath $Destination -Recurse -Force
        }
    }

    if (-not $PSCmdlet.ShouldProcess($Destination, "Copiar Claude Desktop desde $Source")) { return }

    Write-Note "Copiando $Source"
    Write-Note "     ->  $Destination"
    # /XJ: no seguir junctions ni enlaces duros, que los paquetes MSIX si usan.
    $null = robocopy $Source $Destination /E /XJ /COPY:DAT /DCOPY:DA /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
    $rc = $LASTEXITCODE
    # robocopy usa 0-7 como exito (1 = se copiaron archivos). Se normaliza para
    # que el codigo de salida del script no herede un "1" que parece error.
    $global:LASTEXITCODE = 0
    if ($rc -ge 8) {
        throw "robocopy fallo (codigo $rc). Probablemente por permisos de WindowsApps."
    }
}

function Copy-McpConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$DestinationDir,
        [switch]$Overwrite
    )

    $srcDir = Join-Path $env:APPDATA 'Claude'
    $src    = Join-Path $srcDir 'claude_desktop_config.json'
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Warn "No hay claude_desktop_config.json en $srcDir; no se copian MCPs."
        return
    }

    # claude_desktop_config.json mezcla los MCP servers con preferencias de UI
    # ligadas a la cuenta. Se extrae SOLO el nodo mcpServers para no arrastrar
    # ajustes de una cuenta a otra.
    try {
        $srcJson = Get-Content -LiteralPath $src -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warn "No se pudo leer $src como JSON; no se copian MCPs."
        return
    }

    $servers = $null
    if ($srcJson.PSObject.Properties.Name -contains 'mcpServers') { $servers = $srcJson.mcpServers }
    $names = @()
    if ($servers) { $names = @($servers.PSObject.Properties.Name) }

    if ($names.Count -eq 0) {
        Write-Note 'Tu perfil actual no tiene MCP servers configurados: no hay nada que copiar.'
        return
    }

    $dst = Join-Path $DestinationDir 'claude_desktop_config.json'
    if ((Test-Path -LiteralPath $dst) -and -not $Overwrite) {
        Write-Note "Ya hay config MCP en $DestinationDir (usa -Force para sobrescribir)."
        return
    }

    if (-not $PSCmdlet.ShouldProcess($dst, "Copiar $($names.Count) MCP server(s)")) { return }

    # Si el destino ya tiene config, se conserva y solo se reemplaza mcpServers.
    $out = [pscustomobject]@{}
    if (Test-Path -LiteralPath $dst) {
        try { $out = Get-Content -LiteralPath $dst -Raw | ConvertFrom-Json } catch { $out = [pscustomobject]@{} }
    }
    if ($out.PSObject.Properties.Name -contains 'mcpServers') { $out.mcpServers = $servers }
    else { $out | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue $servers }

    # Sin BOM: el parser JSON de la app no lo tolera.
    $json = $out | ConvertTo-Json -Depth 32
    [IO.File]::WriteAllText($dst, $json, (New-Object Text.UTF8Encoding($false)))
    Write-Note "MCPs copiados ($($names -join ', ')) -> $dst"
}

# --- Lanzador por perfil -----------------------------------------------------
# Los accesos directos no apuntan al .exe: apuntan a un lanzador que primero
# comprueba si Claude se actualizo y, si hace falta, refresca la copia portable.

$script:LauncherPs1 = @'
# Lanzador de un perfil de Claude Desktop.
# Comprueba si hay una version nueva de Claude antes de abrir la ventana.
# Lo genera Setup-ClaudeMulti.ps1: no lo edites a mano, se sobrescribe.
param([Parameter(Mandatory)][string]$ProfileName)

$ErrorActionPreference = 'Stop'
$base    = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgFile = Join-Path $base 'config.json'

function Show-Error {
    param([string]$Message)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show($Message, 'Claude Multi Instancia',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    } catch { Write-Host $Message }
    exit 1
}

if (-not (Test-Path -LiteralPath $cfgFile)) {
    Show-Error "No se encontro config.json en $base.`n`nVuelve a ejecutar Setup-ClaudeMulti.bat."
}
$cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
$prof = $cfg.profiles | Where-Object { $_.name -eq $ProfileName } | Select-Object -First 1
if (-not $prof) {
    Show-Error "El perfil '$ProfileName' ya no esta configurado.`n`nVuelve a ejecutar Setup-ClaudeMulti.bat."
}

# Perfil por defecto sobre el paquete de la Store: Windows lo actualiza solo.
if ($prof.useStore -and $cfg.aumid) {
    Start-Process 'explorer.exe' "shell:AppsFolder\$($cfg.aumid)"
    exit 0
}

function Get-InstalledVersion {
    if ($cfg.mode -eq 'Msix') {
        $pkg = Get-AppxPackage -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -match 'Claude' -or $_.Publisher -match 'Anthropic' } |
               Select-Object -First 1
        if ($pkg) { return [string]$pkg.Version }
        return $null
    }
    try {
        $fi = [Diagnostics.FileVersionInfo]::GetVersionInfo($cfg.sourceExe)
        if ($fi.FileVersion) { return $fi.FileVersion.Trim() }
    } catch { }
    return $null
}

function Test-PortableBusy {
    if (-not $cfg.portableDir) { return $false }
    $prefix = $cfg.portableDir.TrimEnd('\') + '\'
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }
        catch { $false }
    }
    return (@($procs).Count -gt 0)
}

# --- Comprobar si hay version nueva -----------------------------------------
$exe    = $prof.exe
$update = $false

if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
    $update = $true
}
elseif ($cfg.mode -eq 'Msix') {
    $stampFile = Join-Path $cfg.portableDir '.claude-multi.json'
    $stampVer  = $null
    if (Test-Path -LiteralPath $stampFile) {
        try { $stampVer = (Get-Content -LiteralPath $stampFile -Raw | ConvertFrom-Json).version } catch { }
    }
    $installed = Get-InstalledVersion
    if ($installed -and $stampVer -and $installed -ne $stampVer) { $update = $true }
}

if ($update -and (Test-PortableBusy)) {
    # No se puede reemplazar la copia con Claude abierto desde ella.
    $update = $false
}

if ($update) {
    $setup = Join-Path $base 'Setup-ClaudeMulti.ps1'
    if (Test-Path -LiteralPath $setup) {
        # Start-Process une los argumentos con espacios y NO los entrecomilla:
        # hay que citar a mano o una ruta como "C:\Users\A Nombre\..." se parte.
        $names = @($cfg.profiles | ForEach-Object { '"' + $_.name + '"' })
        $argv  = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$setup`"", '-Profiles') + $names
        # Ventana visible: la copia tarda y el usuario debe ver que pasa algo.
        Start-Process 'powershell.exe' -ArgumentList $argv -Wait
        try {
            $cfg  = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
            $prof = $cfg.profiles | Where-Object { $_.name -eq $ProfileName } | Select-Object -First 1
            if ($prof) { $exe = $prof.exe }
        } catch { }
    }
}

if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
    Show-Error "No se encontro el ejecutable de Claude:`n$exe`n`nEjecuta Setup-ClaudeMulti.bat para repararlo."
}

Start-Process -FilePath $exe -ArgumentList "--user-data-dir=`"$($prof.dataDir)`""
'@

# wscript lanza PowerShell oculto: sin parpadeo de consola negra al abrir.
$script:LauncherVbs = @'
Option Explicit
Dim sh, fso, base, ps1, prof, cmd
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
ps1  = base & "\Launch-ClaudeProfile.ps1"
If WScript.Arguments.Count > 0 Then
    prof = WScript.Arguments(0)
Else
    prof = ""
End If
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """ -ProfileName """ & prof & """"
sh.Run cmd, 0, False
'@

function Install-Launcher {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][string]$HomePath)

    if (-not (Test-Path -LiteralPath $HomePath)) {
        New-Item -ItemType Directory -Path $HomePath -Force | Out-Null
    }
    if (-not $PSCmdlet.ShouldProcess($HomePath, 'Instalar lanzador de perfiles')) { return }

    $enc = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $HomePath 'Launch-ClaudeProfile.ps1'), $script:LauncherPs1, $enc)
    [IO.File]::WriteAllText((Join-Path $HomePath 'launch.vbs'), $script:LauncherVbs, $enc)

    # Copia del propio setup, para que el lanzador pueda actualizar aunque
    # muevas o borres la carpeta del repositorio.
    $self = $PSCommandPath
    $dest = Join-Path $HomePath 'Setup-ClaudeMulti.ps1'
    if ($self -and (Test-Path -LiteralPath $self)) {
        if ([IO.Path]::GetFullPath($self) -ne [IO.Path]::GetFullPath($dest)) {
            Copy-Item -LiteralPath $self -Destination $dest -Force
        }
    }
}

function Write-LauncherConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$HomePath,
        [Parameter(Mandatory)]$Config
    )
    if (-not $PSCmdlet.ShouldProcess((Join-Path $HomePath 'config.json'), 'Escribir configuracion')) { return }
    $json = $Config | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText((Join-Path $HomePath 'config.json'), $json, (New-Object Text.UTF8Encoding($false)))
}

function Get-ProfileLabel {
    param([string]$Name, [int]$Index)
    if ($Index -eq 0) { return (Get-I18nStr 'ProfileLabelOriginal' @($Name)) }
    return (Get-I18nStr 'ProfileLabelExtra' @($Name))
}

function Invoke-Revert {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string[]]$Names,
        [Parameter(Mandatory)][string]$PortablePath,
        [switch]$SkipConfirm
    )

    $desktop = [Environment]::GetFolderPath('Desktop')

    Write-Step 'Borrando accesos directos...'
    foreach ($n in $Names) {
        foreach ($label in @("Claude - $n (perfil actual)", "Claude - $n")) {
            $lnk = Join-Path $desktop "$label.lnk"
            if (Test-Path -LiteralPath $lnk) {
                if ($PSCmdlet.ShouldProcess($lnk, 'Eliminar acceso directo')) {
                    Remove-Item -LiteralPath $lnk -Force
                    Write-Ok "Borrado: $label.lnk"
                }
            }
        }
    }

    # El primer perfil usa %APPDATA%\Claude, que NUNCA se toca.
    Write-Step 'Borrando carpetas de datos de los perfiles extra...'
    $dataDirs = @()
    foreach ($n in ($Names | Select-Object -Skip 1)) {
        $d = Join-Path $env:APPDATA "Claude-$n"
        if (Test-Path -LiteralPath $d) { $dataDirs += $d }
    }

    if ($dataDirs.Count -eq 0) {
        Write-Note 'No hay carpetas de perfiles extra que borrar.'
    }
    else {
        $go = $SkipConfirm
        if (-not $go) {
            $list = ($dataDirs -join "`n      ")
            try {
                $go = $PSCmdlet.ShouldContinue(
                    "Se van a borrar estas carpetas y con ellas la sesion y los MCPs de esos perfiles:`n      $list`n`nContinuar?",
                    'Borrar datos de perfiles')
            }
            catch {
                # Host no interactivo: no se puede confirmar un borrado de datos.
                Write-Warn 'No se puede pedir confirmacion en este host.'
                Write-Note 'Anade -Force para borrar las carpetas de datos sin preguntar.'
                $go = $false
            }
        }
        if ($go) {
            foreach ($d in $dataDirs) {
                if ($PSCmdlet.ShouldProcess($d, 'Eliminar carpeta de datos del perfil')) {
                    Remove-Item -LiteralPath $d -Recurse -Force
                    Write-Ok "Borrado: $d"
                }
            }
        }
        else {
            Write-Note 'Carpetas de datos conservadas.'
        }
    }

    Write-Step 'Borrando lanzador e iconos...'
    if (Test-Path -LiteralPath $script:HomeDir) {
        if ($PSCmdlet.ShouldProcess($script:HomeDir, 'Eliminar lanzador, iconos y configuracion')) {
            Remove-Item -LiteralPath $script:HomeDir -Recurse -Force
            Write-Ok "Borrado: $script:HomeDir"
        }
    }
    else {
        Write-Note "No existe $script:HomeDir."
    }

    Write-Step 'Borrando la copia portable...'
    if (Test-Path -LiteralPath $PortablePath) {
        if ($PSCmdlet.ShouldProcess($PortablePath, 'Eliminar copia portable')) {
            Remove-Item -LiteralPath $PortablePath -Recurse -Force
            Write-Ok "Borrado: $PortablePath"
        }
    }
    else {
        Write-Note "No existe $PortablePath."
    }

    Write-Host ''
    Write-Ok "Intacto: $(Join-Path $env:APPDATA 'Claude') (tu perfil original)."
}

function Get-ConfiguredProfiles {
    $cfgFile = Join-Path $script:HomeDir 'config.json'
    if (Test-Path -LiteralPath $cfgFile) {
        try {
            $cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
            if ($cfg.profiles) {
                $names = @($cfg.profiles | ForEach-Object { $_.name })
                if ($names.Count -gt 0) { return $names }
            }
        } catch { }
    }
    return @()
}

function Get-ConfiguredProfileObjects {
    $cfgFile = Join-Path $script:HomeDir 'config.json'
    if (Test-Path -LiteralPath $cfgFile) {
        try {
            $cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
            if ($cfg.profiles) {
                return @($cfg.profiles)
            }
        } catch { }
    }
    return @()
}

function Get-ProfileNote {
    param([string]$Name)
    $profs = Get-ConfiguredProfileObjects
    $found = $profs | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if ($found -and $found.note) { return $found.note }
    return $null
}

function Edit-ProfileNotes {
    $profs = Get-ConfiguredProfileObjects
    if ($profs.Count -eq 0) {
        Write-Warn (Get-I18nStr 'NotFound')
        return
    }

    Write-Host ''
    Write-Host '--- Asignar Nota / Correo a Perfil ---' -ForegroundColor Cyan
    for ($i = 0; $i -lt $profs.Count; $i++) {
        $noteStr = $(if ($profs[$i].note) { " ($($profs[$i].note))" } else { '' })
        Write-Host "  [$($i+1)] $($profs[$i].name)$noteStr"
    }
    Write-Host ''
    $sel = Read-Host 'Selecciona el numero de perfil a editar (vacio para cancelar)'
    [int]$idx = 0
    if ([int]::TryParse($sel, [ref]$idx) -and $idx -ge 1 -and $idx -le $profs.Count) {
        $targetProf = $profs[$idx - 1]
        $newNote = Read-Host "Ingresa la nota/correo para '$($targetProf.name)' (vacio para borrar)"
        if ($targetProf.PSObject.Properties.Name -contains 'note') {
            $targetProf.note = $newNote.Trim()
        } else {
            $targetProf | Add-Member -NotePropertyName 'note' -NotePropertyValue $newNote.Trim()
        }

        $cfgFile = Join-Path $script:HomeDir 'config.json'
        if (Test-Path -LiteralPath $cfgFile) {
            try {
                $cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
                $cfg.profiles = $profs
                $json = $cfg | ConvertTo-Json -Depth 8
                [IO.File]::WriteAllText($cfgFile, $json, (New-Object Text.UTF8Encoding($false)))
                Write-Ok "Nota de '$($targetProf.name)' actualizada."
            } catch {
                Write-Warn "No se pudo actualizar config.json: $($_.Exception.Message)"
            }
        }
    }
}

function Invoke-HealthCheck {
    Write-Host ''
    Write-Host '=============================================================' -ForegroundColor White
    Write-Host '  Diagnostico de Salud del Sistema (Health Check)' -ForegroundColor White
    Write-Host '=============================================================' -ForegroundColor White

    $install = Get-ClaudeInstall
    if ($install) {
        Write-Ok "Ejecutable principal: $($install.Exe)"
        Write-Ok "Modo de instalacion: $($install.Mode)"
        if ($install.Version) { Write-Ok "Version instalada: $($install.Version)" }
    } else {
        Write-Err 'No se detecto instalacion activa de Claude Desktop.'
    }

    if (Test-Path -LiteralPath $script:HomeDir) {
        Write-Ok "Carpeta de lanzadores e iconos: $script:HomeDir [OK]"
    } else {
        Write-Warn "No existe la carpeta de lanzadores: $script:HomeDir"
    }

    $profs = Get-ConfiguredProfileObjects
    if ($profs.Count -gt 0) {
        Write-Host "`nEstado de perfiles configurados:" -ForegroundColor Cyan
        $desktop = [Environment]::GetFolderPath('Desktop')
        foreach ($p in $profs) {
            $n = $p.name
            $dataDir = $p.dataDir
            $exists = Test-Path -LiteralPath $dataDir
            $sizeMB = 0
            if ($exists) {
                try {
                    $bytes = (Get-ChildItem -LiteralPath $dataDir -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    $sizeMB = [math]::Round(($bytes / 1MB), 1)
                } catch { }
            }
            $lnkOriginal = Join-Path $desktop "Claude - $n (perfil actual).lnk"
            $lnkExtra    = Join-Path $desktop "Claude - $n.lnk"
            $hasLnk      = (Test-Path -LiteralPath $lnkOriginal) -or (Test-Path -LiteralPath $lnkExtra)
            
            $noteStr = $(if ($p.note) { " ($($p.note))" } else { '' })
            $statusStr = $(if ($exists) { "$sizeMB MB" } else { 'No creada' })
            $lnkStr    = $(if ($hasLnk) { 'Acceso directo [OK]' } else { 'Acceso directo [FALTA]' })

            if ($exists -and $hasLnk) {
                Write-Ok "$n$noteStr -> $statusStr | $lnkStr"
            } else {
                Write-Warn "$n$noteStr -> $statusStr | $lnkStr"
            }
        }
    } else {
        Write-Note 'No hay perfiles configurados actualmente.'
    }

    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'claude' }
    Write-Host "`nProcesos de Claude en ejecucion: $($procs.Count)" -ForegroundColor Gray
    Write-Host ''
}

function Clear-ProfileCache {
    Write-Host ''
    Write-Host '--- Limpiador de Cache y Archivos Temporales ---' -ForegroundColor Cyan

    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'claude' }
    if ($procs.Count -gt 0) {
        Write-Warn "Hay $($procs.Count) proceso(s) de Claude en ejecucion."
        Write-Warn 'Cierra todas las ventanas de Claude antes de limpiar la cache.'
        return
    }

    $targets = @()
    $mainDir = Join-Path $env:APPDATA 'Claude'
    if (Test-Path -LiteralPath $mainDir) { $targets += $mainDir }
    Get-ChildItem -LiteralPath $env:APPDATA -Filter 'Claude-*' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $targets += $_.FullName
    }

    if ($targets.Count -eq 0) {
        Write-Note 'No se encontraron carpetas de perfiles para limpiar.'
        return
    }

    $cacheSubdirs = @('Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'blob_storage', 'Crashpad', 'logs')
    [long]$totalFreedBytes = 0

    foreach ($dir in $targets) {
        foreach ($sub in $cacheSubdirs) {
            $path = Join-Path $dir $sub
            if (Test-Path -LiteralPath $path) {
                try {
                    $bytes = (Get-ChildItem -LiteralPath $path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
                    $totalFreedBytes += $bytes
                } catch { }
            }
        }
    }

    $freedMB = [math]::Round(($totalFreedBytes / 1MB), 2)
    Write-Ok "Limpieza completada. Espacio en disco liberado: $freedMB MB"
    Write-Host ''
}

function Export-ProfileBackup {
    Write-Host ''
    Write-Host '--- Respaldar Perfiles (Backup .zip) ---' -ForegroundColor Cyan

    $desktop = [Environment]::GetFolderPath('Desktop')
    $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $zipPath = Join-Path $desktop "ClaudeMulti_Backup_$timestamp.zip"

    $tempDir = Join-Path $env:TEMP "ClaudeMulti_Backup_$timestamp"
    if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        if (Test-Path -LiteralPath $script:HomeDir) {
            Copy-Item -LiteralPath $script:HomeDir -Destination (Join-Path $tempDir 'ClaudeMulti') -Recurse -Force
        }

        $profDir = Join-Path $tempDir 'Profiles'
        New-Item -ItemType Directory -Path $profDir -Force | Out-Null

        $targets = @()
        $mainDir = Join-Path $env:APPDATA 'Claude'
        if (Test-Path -LiteralPath $mainDir) { Copy-Item -LiteralPath $mainDir -Destination (Join-Path $profDir 'Claude') -Recurse -Force }
        Get-ChildItem -LiteralPath $env:APPDATA -Filter 'Claude-*' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $profDir $_.Name) -Recurse -Force
        }

        # Excluir cache pesada dentro de la copia de backup
        $cacheSubdirs = @('Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'blob_storage', 'Crashpad', 'logs')
        Get-ChildItem -LiteralPath $profDir -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object { $cacheSubdirs -contains $_.Name } | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }

        Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -Force
        $zipBytes = (Get-Item -LiteralPath $zipPath).Length
        $zipMB = [math]::Round(($zipBytes / 1MB), 2)

        Write-Ok "Backup creado exitosamente en el Escritorio:"
        Write-Note "$zipPath ($zipMB MB)"
    }
    catch {
        Write-Err "Error al crear el backup: $($_.Exception.Message)"
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Host ''
}

function Import-ProfileBackup {
    Write-Host ''
    Write-Host '--- Restaurar Perfiles desde Backup (.zip) ---' -ForegroundColor Cyan

    $zipPath = Read-Host 'Ingresa la ruta completa del archivo .zip de backup'
    if ([string]::IsNullOrWhiteSpace($zipPath)) { return }
    $zipPath = $zipPath.Trim('"').Trim("'")

    if (-not (Test-Path -LiteralPath $zipPath)) {
        Write-Warn "No se encontro el archivo: $zipPath"
        return
    }

    $tempDir = Join-Path $env:TEMP "ClaudeMulti_Restore_$(Get-Random)"
    if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

        $homeBackup = Join-Path $tempDir 'ClaudeMulti'
        if (Test-Path -LiteralPath $homeBackup) {
            Copy-Item -LiteralPath $homeBackup -Destination $script:HomeDir -Recurse -Force
            Write-Ok "Configuracion de lanzador restaurada."
        }

        $profBackup = Join-Path $tempDir 'Profiles'
        if (Test-Path -LiteralPath $profBackup) {
            Get-ChildItem -LiteralPath $profBackup -Directory | ForEach-Object {
                $targetAppData = Join-Path $env:APPDATA $_.Name
                Copy-Item -LiteralPath $_.FullName -Destination $targetAppData -Recurse -Force
                Write-Ok "Restaurado perfil: $($_.Name)"
            }
        }

        Write-Ok 'Restauracion completada exitosamente.'
        Write-Note 'Se recomienda ejecutar la opcion [1] del menu para reconstruir accesos directos.'
    }
    catch {
        Write-Err "Error al restaurar el backup: $($_.Exception.Message)"
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Host ''
}

function Show-InteractiveMenu {
    $configuredObjs = Get-ConfiguredProfileObjects
    $configured = @($configuredObjs | ForEach-Object { $_.name })
    $current = $(if ($configured.Count -gt 0) { $configured } else { @('Cuenta1', 'Cuenta2', 'Cuenta3') })

    while ($true) {
        $displayList = @()
        foreach ($c in $current) {
            $note = Get-ProfileNote -Name $c
            if ($note) { $displayList += "$c ($note)" }
            else { $displayList += $c }
        }
        $currStr = $displayList -join ', '

        Write-Host ''
        Write-Host '=============================================================' -ForegroundColor White
        Write-Host ("  " + (Get-I18nStr 'MenuTitle')) -ForegroundColor White
        Write-Host '=============================================================' -ForegroundColor White
        Write-Host ("  " + (Get-I18nStr 'CurrentInstances') + ": [ $currStr ]") -ForegroundColor Cyan
        Write-Host ("  " + (Get-I18nStr 'CopyMcpsLabel') + ":        $(if ($script:CopyMcpConfig) { 'SI' } else { 'NO' })") -ForegroundColor Gray
        Write-Host ''
        Write-Host "  [1] Ejecutar / Actualizar instalacion actual ($currStr)" -ForegroundColor Yellow
        Write-Host '  [2] Especificar cantidad total de instancias (ej: 4 -> Cuenta1..Cuenta4)'
        Write-Host '  [3] Anadir una nueva instancia / perfil (ej: "Cuenta4" o "Trabajo")'
        Write-Host '  [4] Asignar nota / correo a un perfil (ej: trabajo@empresa.com)' -ForegroundColor Green
        Write-Host '  [5] Diagnostico de salud del sistema (Health Check)' -ForegroundColor Green
        Write-Host '  [6] Limpiar cache y archivos temporales (liberar espacio en disco)' -ForegroundColor Green
        Write-Host '  [7] Crear Backup de perfiles (.zip)' -ForegroundColor Green
        Write-Host '  [8] Restaurar perfiles desde Backup (.zip)' -ForegroundColor Green
        Write-Host '  [9] Alternar copia de MCPs a nuevos perfiles'
        Write-Host '  [10] Revertir / Eliminar perfiles'
        Write-Host '  [0] Salir'
        Write-Host ''
        $opt = Read-Host 'Selecciona una opcion (0-10)'

        switch ($opt.Trim()) {
            '1' {
                return @{ Profiles = $current }
            }
            '2' {
                Write-Host ''
                $numStr = Read-Host (Get-I18nStr 'EnterTotalNum')
                [int]$num = 0
                if ([int]::TryParse($numStr, [ref]$num) -and $num -ge 1) {
                    $newList = @()
                    for ($i = 1; $i -le $num; $i++) {
                        if ($i -le $current.Count -and $current[$i-1]) {
                            $newList += $current[$i-1]
                        } else {
                            $newList += "Cuenta$i"
                        }
                    }
                    return @{ Profiles = $newList }
                } else {
                    Write-Warn (Get-I18nStr 'InvalidNum')
                }
            }
            '3' {
                Write-Host ''
                $newName = Read-Host (Get-I18nStr 'EnterNewName')
                if ($newName) { $newName = $newName.Trim() }
                if (-not [string]::IsNullOrWhiteSpace($newName)) {
                    if ($current -contains $newName) {
                        Write-Warn (Get-I18nStr 'ProfileExists' @($newName))
                    } else {
                        $newList = @($current) + $newName
                        return @{ Profiles = $newList }
                    }
                } else {
                    Write-Warn (Get-I18nStr 'NameCannotBeEmpty')
                }
            }
            '4' {
                Edit-ProfileNotes
            }
            '5' {
                Invoke-HealthCheck
            }
            '6' {
                Clear-ProfileCache
            }
            '7' {
                Export-ProfileBackup
            }
            '8' {
                Import-ProfileBackup
            }
            '9' {
                $script:CopyMcpConfig = -not $script:CopyMcpConfig
                Write-Ok (if ($script:CopyMcpConfig) { Get-I18nStr 'CopyMcpsActive' } else { Get-I18nStr 'CopyMcpsInactive' })
            }
            '10' {
                Write-Host ''
                Write-Warn (Get-I18nStr 'WarnDeleteData')
                $ans = Read-Host (Get-I18nStr 'ConfirmRevert')
                if ($ans -eq 'S' -or $ans -eq 's' -or $ans -eq 'Y' -or $ans -eq 'y') {
                    return @{ Profiles = $current; Revert = $true }
                }
            }
            '0' {
                Write-Host (Get-I18nStr 'OpCancelled')
                exit 0
            }
            default {
                Write-Warn (Get-I18nStr 'InvalidOpt')
            }
        }
    }
}

# ------------------------------------------------------------------- main ---

Write-Host ''
Write-Host '=============================================================' -ForegroundColor White
Write-Host ("  " + (Get-I18nStr 'HeaderTitle')) -ForegroundColor White
Write-Host '=============================================================' -ForegroundColor White

if (-not $PSBoundParameters.ContainsKey('Profiles') -and -not $Revert) {
    if ([Environment]::UserInteractive) {
        $menuRes = Show-InteractiveMenu
        if ($menuRes) {
            if ($menuRes.Profiles) { $Profiles = $menuRes.Profiles }
            if ($menuRes.Revert)   { $Revert = $true }
        }
    }
}

# Al invocar via .bat, cmd entrega "-Profiles A,B" como UN solo token y
# powershell -File no lo parte en array. Se normaliza aqui para que
# "-Profiles A,B" signifique lo mismo desde cmd que desde PowerShell.
$Profiles = @(
    $Profiles |
    ForEach-Object { $_ -split ',' } |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ }
)

Assert-ProfileNames -Names $Profiles

if ($Revert) {
    Invoke-Revert -Names $Profiles -PortablePath $PortableDir -SkipConfirm:$Force
    Write-Host ''
    exit 0
}

Write-Step 'Buscando la instalacion de Claude Desktop...'
$install = Get-ClaudeInstall

if (-not $install) {
    Write-Err 'No se encontro Claude Desktop en este equipo.'
    Write-Note 'Rutas revisadas: %LOCALAPPDATA%\AnthropicClaude, %ProgramFiles%\Claude y paquetes MSIX.'
    Write-Note 'Instala Claude Desktop y vuelve a ejecutar este script.'
    exit 1
}

Write-Ok "Modo de instalacion: $($install.Mode)"
Write-Note "Carpeta: $($install.Dir)"
if ($install.Version) { Write-Note "Version instalada: $($install.Version)" }

$targetExe   = $install.Exe
$portableNew = $false

# --- Caso MSIX: se necesita copia portable ----------------------------------
if ($install.Mode -eq 'Msix') {
    Write-Step 'Instalacion tipo MSIX detectada (Microsoft Store).'
    Write-Note 'Windows no permite lanzar el .exe desde WindowsApps con parametros,'
    Write-Note 'asi que hay que hacer una copia portable en una carpeta normal.'

    # --- Comprobar si la copia portable esta al dia -------------------------
    $stamp      = Get-PortableStamp -PortablePath $PortableDir
    $needsCopy  = $true
    $copyReason = 'No hay copia portable todavia.'

    if ($Force) {
        $copyReason = 'Se pidio -Force: se rehace la copia.'
    }
    elseif ($stamp -and (Test-Path -LiteralPath $stamp.exe)) {
        if ($stamp.version -eq $install.Version) {
            $needsCopy  = $false
            $targetExe  = $stamp.exe
            Write-Ok "Copia portable al dia (version $($stamp.version)). No hay nada que actualizar."
        }
        else {
            $copyReason = "Claude se actualizo: $($stamp.version) -> $($install.Version). Actualizando la copia..."
        }
    }
    elseif ($stamp) {
        $copyReason = 'La copia portable esta incompleta o movida: se rehace.'
    }
    elseif (Test-Path -LiteralPath $PortableDir) {
        $copyReason = 'Hay una copia portable sin sello de version: se rehace para poder controlarla.'
    }

    if ($needsCopy) {
        Write-Note $copyReason

        # No se puede reemplazar la copia con la app abierta desde ella.
        $running = @(Get-PortableProcess -PortablePath $PortableDir)
        if ($running.Count -gt 0) {
            Write-Warn "Hay $($running.Count) proceso(s) de Claude corriendo desde $PortableDir."
            Write-Warn 'No se puede reemplazar la copia mientras esten abiertos.'
            Write-Note 'Cierra esas ventanas de Claude y vuelve a ejecutar Setup-ClaudeMulti.bat.'
            Write-Note 'Por ahora se sigue usando la copia actual.'
            $needsCopy = $false
            if ($stamp -and (Test-Path -LiteralPath $stamp.exe)) {
                $targetExe = $stamp.exe
            }
            else {
                $found = Get-ChildItem -LiteralPath $PortableDir -Filter 'claude.exe' -Recurse `
                           -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $found) { throw "No se encontro claude.exe dentro de $PortableDir" }
                $targetExe = $found.FullName
            }
        }
    }

    # Se intenta la copia primero: en muchos equipos WindowsApps es legible
    # para el usuario y no hace falta ni admin ni tocar ACLs.
    $copied = -not $needsCopy
    if ($needsCopy) {
        $portableNew = $true
        try {
            Copy-ToPortable -Source $install.Dir -Destination $PortableDir -Overwrite
            $copied = $true
        }
        catch {
            Write-Warn $_.Exception.Message
        }
    }

    if (-not $copied) {
        # Puede fallar por la app abierta desde la copia, no solo por permisos.
        if (@(Get-PortableProcess -PortablePath $PortableDir).Count -gt 0) {
            Write-Host ''
            Write-Err  'La actualizacion fallo: hay Claude abierto desde la copia portable.'
            Write-Note 'Cierra todas las ventanas de Claude y vuelve a ejecutar el .bat.'
            exit 1
        }

        Write-Host ''
        Write-Warn 'La copia fallo por los permisos restrictivos de WindowsApps.'
        Write-Warn 'La solucion es dar permiso de lectura al grupo Administradores'
        Write-Warn 'sobre esa carpeta. ESTO MODIFICA LOS PERMISOS DE UNA CARPETA'
        Write-Warn 'PROTEGIDA DE WINDOWS y en casos raros puede afectar las'
        Write-Warn 'actualizaciones automaticas de la app.'

        $allowed = [bool]$GrantWindowsAppsRead
        if (-not $allowed) {
            try {
                $allowed = $PSCmdlet.ShouldContinue(
                    "Dar lectura al grupo Administradores sobre $($install.Dir)?",
                    'Permisos de WindowsApps')
            }
            catch {
                Write-Err 'Ejecucion no interactiva: usa -GrantWindowsAppsRead para autorizarlo.'
                $allowed = $false
            }
        }

        if (-not $allowed) {
            Write-Note 'Cancelado. Alternativa sin tocar permisos: crear un segundo'
            Write-Note 'usuario de Windows y usar "Ejecutar como otro usuario".'
            exit 1
        }

        if (-not (Test-Admin)) {
            Write-Err 'Este paso necesita permisos de Administrador.'
            Write-Note 'Cierra esta ventana y ejecuta Setup-ClaudeMulti.bat con boton'
            Write-Note 'derecho -> "Ejecutar como administrador".'
            exit 1
        }

        if ($PSCmdlet.ShouldProcess($install.Dir, 'takeown + icacls (lectura para Administradores)')) {
            Write-Note 'Tomando posesion de la carpeta del paquete...'
            & takeown.exe /F "$($install.Dir)" /R /D S | Out-Null
            Write-Note 'Otorgando lectura a Administradores...'
            & icacls.exe "$($install.Dir)" /grant '*S-1-5-32-544:(OI)(CI)(RX)' /T /C /Q | Out-Null

            Copy-ToPortable -Source $install.Dir -Destination $PortableDir -Overwrite
        }
    }

    if ($portableNew) {
        # Resolver el exe dentro de la copia respetando su ruta relativa
        # (en MSIX suele ser <paquete>\app\claude.exe, no la raiz).
        $portableExe = $null
        if ($install.Exe) {
            $baseDir = $install.Dir.TrimEnd('\')
            if ($install.Exe.StartsWith($baseDir, [StringComparison]::OrdinalIgnoreCase)) {
                $rel         = $install.Exe.Substring($baseDir.Length).TrimStart('\')
                $portableExe = Join-Path $PortableDir $rel
            }
        }
        if (-not $portableExe -or -not (Test-Path -LiteralPath $portableExe)) {
            $found = Get-ChildItem -LiteralPath $PortableDir -Filter 'claude.exe' -Recurse `
                       -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $portableExe = $found.FullName
            }
            elseif (-not $WhatIfPreference) {
                throw "No se encontro claude.exe dentro de $PortableDir"
            }
            elseif (-not $portableExe) {
                $portableExe = Join-Path $PortableDir 'claude.exe'
            }
        }
        $targetExe = $portableExe

        # Sellar la version: es lo que permite detectar la proxima actualizacion.
        if (-not $WhatIfPreference) {
            Set-PortableStamp -PortablePath $PortableDir -Version $install.Version `
                              -Exe $targetExe -Source $install.Dir
        }
        Write-Ok "Copia portable lista (version $($install.Version)): $targetExe"
    }
}
else {
    Write-Ok 'No hace falta copia portable: el ejecutable se puede lanzar directo.'
    if ($install.Exe -match '\\app-[0-9]') {
        Write-Warn 'El ejecutable esta dentro de una carpeta con numero de version.'
        Write-Warn 'Cuando Claude se actualice, esa ruta desaparece y los accesos'
        Write-Warn 'directos dejaran de funcionar: vuelve a correr este script.'
    }
}

if (-not $targetExe -or (-not (Test-Path -LiteralPath $targetExe) -and -not $WhatIfPreference)) {
    throw 'No se pudo determinar el ejecutable de Claude Desktop.'
}

# --- Iconos y lanzador -------------------------------------------------------
$iconDir = Join-Path $script:HomeDir 'icons'

Write-Step 'Generando iconos de color por perfil...'
$icons = @{}
for ($i = 0; $i -lt $Profiles.Count; $i++) {
    $n = $Profiles[$i]
    try {
        $ic = New-ProfileIcon -Name $n -Index $i -SourceExe $targetExe -OutDir $iconDir
        $icons[$n] = $ic
        Write-Ok "$n -> $($ic.Color)"
    }
    catch {
        Write-Warn "No se pudo generar el icono de '$n': $($_.Exception.Message)"
        Write-Note 'Se usara el icono normal de Claude.'
        $icons[$n] = $null
    }
}

if (-not $NoLauncher) {
    Write-Step 'Instalando lanzador (comprueba actualizaciones antes de abrir)...'
    Install-Launcher -HomePath $script:HomeDir
    Write-Ok $script:HomeDir
}

# --- Crear los accesos directos ---------------------------------------------
Write-Step 'Creando accesos directos en el Escritorio...'

$wscript  = Join-Path $env:WINDIR 'System32\wscript.exe'
$vbs      = Join-Path $script:HomeDir 'launch.vbs'
$created  = @()
$cfgProfs = @()

for ($i = 0; $i -lt $Profiles.Count; $i++) {
    $name     = $Profiles[$i]
    $label    = Get-ProfileLabel -Name $name -Index $i
    $iconPath = $(if ($icons[$name]) { $icons[$name].Path } else { $targetExe })
    $color    = $(if ($icons[$name]) { $icons[$name].Color } else { '-' })
    $useStore = ($i -eq 0 -and $install.Mode -eq 'Msix' -and $install.Aumid)

    if ($i -eq 0) {
        # Primer perfil: carpeta de datos por defecto -> conserva tu sesion actual.
        $dataDir = Join-Path $env:APPDATA 'Claude'
    }
    else {
        $dataDir = Join-Path $env:APPDATA "Claude-$name"
        if (-not (Test-Path -LiteralPath $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }
        if ($CopyMcpConfig) {
            Copy-McpConfig -DestinationDir $dataDir -Overwrite:$Force
        }
    }

    $note    = Get-ProfileNote -Name $name
    $noteStr = $(if ($note) { " ($note)" } else { '' })

    if ($useStore) {
        # El paquete de la Store se actualiza solo: no hace falta lanzador.
        $lnk = New-ClaudeShortcut -Name $label `
                 -Target      (Join-Path $env:WINDIR 'explorer.exe') `
                 -Arguments   "shell:AppsFolder\$($install.Aumid)" `
                 -IconPath    $iconPath `
                 -Description "Claude Desktop - perfil '$name'$noteStr (paquete de la Store)"
        $via = 'Store'
    }
    elseif ($NoLauncher) {
        $arg = $(if ($i -eq 0) { '' } else { "--user-data-dir=`"$dataDir`"" })
        $lnk = New-ClaudeShortcut -Name $label -Target $targetExe -Arguments $arg `
                 -IconPath $iconPath -Description "Claude Desktop - perfil '$name'$noteStr en $dataDir"
        $via = 'Exe'
    }
    else {
        $lnk = New-ClaudeShortcut -Name $label `
                 -Target      $wscript `
                 -Arguments   "`"$vbs`" `"$name`"" `
                 -IconPath    $iconPath `
                 -Description "Claude Desktop - perfil '$name'$noteStr (comprueba actualizaciones al abrir)"
        $via = 'Lanzador'
    }

    $cfgProfs += [pscustomobject]@{
        name     = $name
        note     = $note
        dataDir  = $dataDir
        useStore = [bool]$useStore
        exe      = $targetExe
        icon     = $iconPath
    }
    $created += [pscustomobject]@{
        Perfil = $name
        Color  = $color
        Lanza  = $via
        Acceso = Split-Path -Leaf $lnk
    }
    Write-Ok "$label  [$color]"
}

if (-not $NoLauncher) {
    Write-LauncherConfig -HomePath $script:HomeDir -Config ([pscustomobject]@{
        mode        = $install.Mode
        aumid       = $install.Aumid
        portableDir = $PortableDir
        sourceExe   = $install.Exe
        version     = $install.Version
        profiles    = $cfgProfs
    })
}

# --- Resumen -----------------------------------------------------------------
Write-Host ''
Write-Host '=============================================================' -ForegroundColor White
Write-Host '  Listo' -ForegroundColor Green
Write-Host '=============================================================' -ForegroundColor White
$created | Format-Table -AutoSize | Out-String | Write-Host

Write-Host 'Como usarlo:' -ForegroundColor White
Write-Note 'Abre el primer acceso directo -> es tu sesion de siempre.'
Write-Note 'Abre el segundo y tercer acceso directo -> pediran login. Entra con cada cuenta.'
Write-Note 'Las tres ventanas pueden estar abiertas al mismo tiempo.'
Write-Note 'Cada acceso directo lleva una insignia de color con su inicial.'
if (-not $NoLauncher) {
    Write-Note 'Al abrir un perfil se comprueba si Claude tiene version nueva y,'
    Write-Note 'si la hay, se actualiza la copia antes de arrancar la ventana.'
}
Write-Host ''
Write-Host 'Importante:' -ForegroundColor Yellow
Write-Note 'Cowork corre en una VM Hyper-V unica por maquina: solo una instancia'
Write-Note 'puede usar Cowork a la vez.'
if (-not $CopyMcpConfig) {
    Write-Note 'Los perfiles nuevos arrancan SIN MCP servers. Usa -CopyMcpConfig para'
    Write-Note 'copiarles los que tengas en el perfil por defecto.'
}
if ($install.Mode -eq 'Msix') {
    if ($install.Aumid) {
        Write-Note 'El primer perfil se lanza por el paquete de la Store: se actualiza solo.'
    }
    Write-Note 'La copia portable (perfiles extra) se refresca ejecutando de nuevo'
    Write-Note 'Setup-ClaudeMulti.bat: detecta la version nueva y la copia sola.'
}
Write-Note 'Para revertir: vuelve a correr este script con -Revert y los mismos -Profiles.'
Write-Host ''

exit 0
