$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Una excepcion suelta dentro de un evento abre el cuadro "Excepcion no
# controlada" y dejaria el test colgado esperando un clic. Se captura para que
# el fallo salga por consola.
[System.Windows.Forms.Application]::SetUnhandledExceptionMode(
    [System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({ param($sender, $eventArgs)
    $script:threadError = $eventArgs.Exception.Message
})
$script:threadError = ''

$sourcePath = Join-Path $PSScriptRoot '..\Setup-ClaudeMulti.ps1'
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$null, [ref]$errors)
if ($errors.Count) { throw ($errors.Message -join '; ') }
foreach ($name in @('Start-GuiSetupJob', 'ConvertFrom-ChildErrorText')) {
    $functionAst = $ast.Find({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq $name
    }, $true)
    if (-not $functionAst) { throw "$name was not found" }
    Invoke-Expression $functionAst.Extent.Text
}
# Dobles de lo que el manejador usa solo para dar el aviso final.
function Get-I18nStr { param([string]$Key, [object[]]$FormatArgs) "$Key($($FormatArgs -join ','))" }
function Get-RunLogPath { Join-Path $testRoot 'last-run.log' }

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ClaudeMulti-gui-test-' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($testRoot)
$stub = Join-Path $testRoot 'Slow Setup.ps1'
$stubSource = @'
[CmdletBinding(PositionalBinding = $false)]
param([string[]]$Profiles, [string]$PortableDir, [string]$Language)
Write-Output "started:$($Profiles -join '|')"
Start-Sleep -Milliseconds 1200
Write-Output 'finished'
exit 0
'@
[IO.File]::WriteAllText($stub, $stubSource, (New-Object Text.UTF8Encoding($false)))

# Este falla y, ademas, escribe en el flujo de errores: el hijo lo serializa
# como CLIXML y nada de ese XML debe acabar en el panel.
$stubBad = Join-Path $testRoot 'Bad Setup.ps1'
$stubBadSource = @'
[CmdletBinding(PositionalBinding = $false)]
param([string[]]$Profiles, [string]$PortableDir, [string]$Language)
Write-Output 'empezando'
[Console]::Error.WriteLine('no se encuentra la copia portable')
exit 2
'@
[IO.File]::WriteAllText($stubBad, $stubBadSource, (New-Object Text.UTF8Encoding($false)))

$form = New-Object System.Windows.Forms.Form
$form.ShowInTaskbar = $false
$form.Opacity = 0
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$busy = $false
$refreshed = $false
$PortableDir = Join-Path $testRoot 'portable'
$script:Lang = 'es'
$SharedDir = Join-Path $testRoot 'shared'
$NoLauncher = $false
$GrantWindowsAppsRead = $false
$Force = $false
$script:GuiSetupJob = $null
$script:GuiSetupTimer = $null
function Append-GuiLog { param([string]$Message) $txtLog.AppendText("$Message`r`n") }
function Set-GuiBusy { param([bool]$Busy) $script:busy = $Busy }
function Refresh-ProfileList { $script:refreshed = $true }

try {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    Start-GuiSetupJob -TargetProfiles @('Cuenta1', 'Cuenta dos') -SetupPath $stub
    $watch.Stop()
    if ($watch.ElapsedMilliseconds -gt 700) { throw "GUI call blocked for $($watch.ElapsedMilliseconds) ms" }
    if (-not $script:GuiSetupJob) { throw 'Background process was not registered' }

    $deadline = (Get-Date).AddSeconds(10)
    $watchTimer = New-Object System.Windows.Forms.Timer
    $watchTimer.Interval = 100
    $watchTimer.Add_Tick({
        if (-not $script:GuiSetupJob -or (Get-Date) -ge $deadline) { $form.Close() }
    })
    $watchTimer.Start()
    [void]$form.ShowDialog()
    $watchTimer.Stop()
    $watchTimer.Dispose()
    if ($script:threadError) { throw "Unhandled exception in the GUI timer: $($script:threadError)" }
    if ($script:GuiSetupJob) { throw 'Background process did not finish' }
    if ($txtLog.Text -notmatch 'started:Cuenta1\|Cuenta dos' -or $txtLog.Text -notmatch 'finished') {
        throw "GUI did not receive child output: $($txtLog.Text)"
    }
    if ($script:busy) { throw 'GUI remained busy after completion' }
    if (-not $script:refreshed) { throw 'Profile list was not refreshed' }
    if ($txtLog.Text -match 'LogChildFailed') {
        throw "A successful run was reported as a failure: $($txtLog.Text)"
    }
    Write-Host "PASS: GUI returned in $($watch.ElapsedMilliseconds) ms and streamed background output"

    # --- El hijo falla: se avisa del codigo y no se filtra el CLIXML ---------
    $txtLog.Clear()
    $script:busy = $false
    $script:refreshed = $false
    $form2 = New-Object System.Windows.Forms.Form
    $form2.ShowInTaskbar = $false
    $form2.Opacity = 0
    Start-GuiSetupJob -TargetProfiles @('Cuenta1') -SetupPath $stubBad
    if (-not $script:GuiSetupJob) { throw 'Failing child was not registered' }

    $deadline2 = (Get-Date).AddSeconds(10)
    $watchTimer2 = New-Object System.Windows.Forms.Timer
    $watchTimer2.Interval = 100
    $watchTimer2.Add_Tick({
        if (-not $script:GuiSetupJob -or (Get-Date) -ge $deadline2) { $form2.Close() }
    })
    $watchTimer2.Start()
    [void]$form2.ShowDialog()
    $watchTimer2.Stop()
    $watchTimer2.Dispose()
    $form2.Dispose()

    if ($script:threadError) { throw "Unhandled exception in the GUI timer: $($script:threadError)" }
    if ($script:GuiSetupJob) { throw 'Failing child did not finish' }
    if ($txtLog.Text -match 'CLIXML' -or $txtLog.Text -match '_x000D_' -or $txtLog.Text -match '<Objs') {
        throw "CLIXML leaked into the GUI panel: $($txtLog.Text)"
    }
    if ($txtLog.Text -notmatch 'copia portable') {
        throw "The child error text was lost: $($txtLog.Text)"
    }
    if ($txtLog.Text -notmatch 'LogChildFailed\(2\)') {
        throw "Exit code 2 was not reported: $($txtLog.Text)"
    }
    if ($script:busy) { throw 'GUI remained busy after a failed run' }
    Write-Host 'PASS: a failing child reports its exit code without leaking CLIXML'
}
finally {
    if ($script:GuiSetupTimer) { $script:GuiSetupTimer.Stop(); $script:GuiSetupTimer.Dispose() }
    if ($script:GuiSetupJob -and -not $script:GuiSetupJob.Process.HasExited) { $script:GuiSetupJob.Process.Kill() }
    $form.Dispose()
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolved) -like 'ClaudeMulti-gui-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
