# Regresion: el temporizador que vigila al proceso hijo remata la operacion
# llamando a Set-GuiBusy y Refresh-ProfileList, que son funciones LOCALES de
# Show-Gui. Un .GetNewClosure() sobre ese bloque lo cuelga del ambito del
# modulo y deja de verlas: el GUI moria con
#   "El termino 'Set-GuiBusy' no se reconoce como nombre de un cmdlet..."
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$sourcePath = Join-Path $PSScriptRoot '..\Setup-ClaudeMulti.ps1'
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$null, [ref]$errors)
if ($errors.Count) { throw ($errors.Message -join '; ') }
$functionAst = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Start-GuiSetupJob'
}, $true)
if (-not $functionAst) { throw 'Start-GuiSetupJob was not found' }
$body = $functionAst.Extent.Text

if ($body -match 'GetNewClosure') {
    throw 'Start-GuiSetupJob uses GetNewClosure: the timer would lose the GUI-local helpers'
}
foreach ($call in @('Set-GuiBusy $false', 'Refresh-ProfileList')) {
    if ($body -notmatch [regex]::Escape($call)) {
        throw "Start-GuiSetupJob no longer calls '$call' when the child finishes"
    }
}

# Comprobacion viva de la regla de ambito en la que se apoya el arreglo. El
# manejador va entero dentro de un try/catch: una excepcion suelta en un evento
# de Windows Forms abre el cuadro de "Excepcion no controlada" y cuelga el test.
function Show-GuiLike {
    param([bool]$UseClosure)

    $form = New-Object System.Windows.Forms.Form
    $form.Opacity = 0
    $form.ShowInTaskbar = $false
    $script:probeForm = $form

    function Set-GuiBusy { param([bool]$Busy) $script:probe += "busy=$Busy;" }

    function Start-Fake {
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 100
        $script:probeTimer = $timer
        $handler = { try { Set-GuiBusy $false } catch { } }
        if ($UseClosure) { $handler = $handler.GetNewClosure() }
        $timer.Add_Tick($handler)
        $timer.Start()
    }

    Start-Fake

    # El vigilante se crea fuera de todo closure, asi siempre cierra el formulario.
    $watchdog = New-Object System.Windows.Forms.Timer
    $watchdog.Interval = 600
    $script:probeWatchdog = $watchdog
    $watchdog.Add_Tick({ $script:probeWatchdog.Stop(); $script:probeForm.Close() })
    $watchdog.Start()

    [void]$form.ShowDialog()
    $script:probeTimer.Stop(); $script:probeTimer.Dispose()
    $watchdog.Dispose()
    $form.Dispose()
}

$script:probe = ''
Show-GuiLike -UseClosure $false
if ($script:probe -notmatch 'busy=False') {
    throw "Timer handler could not reach the GUI-local helper: '$($script:probe)'"
}

$script:probe = ''
Show-GuiLike -UseClosure $true
if ($script:probe -match 'busy=False') {
    throw 'Expected the closure variant to fail; the scope rule under test changed'
}

Write-Host 'PASS: the job timer resolves the GUI-local helpers (no closure)'
