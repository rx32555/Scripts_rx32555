$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$sourcePath = Join-Path $PSScriptRoot '..\Setup-ClaudeMulti.ps1'
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$null, [ref]$errors)
if ($errors.Count) { throw ($errors.Message -join '; ') }
$functionAst = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Start-GuiSetupJob'
}, $true)
if (-not $functionAst) { throw 'Start-GuiSetupJob was not found' }
Invoke-Expression $functionAst.Extent.Text

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
    if ($script:GuiSetupJob) { throw 'Background process did not finish' }
    if ($txtLog.Text -notmatch 'started:Cuenta1\|Cuenta dos' -or $txtLog.Text -notmatch 'finished') {
        throw "GUI did not receive child output: $($txtLog.Text)"
    }
    if ($script:busy) { throw 'GUI remained busy after completion' }
    if (-not $script:refreshed) { throw 'Profile list was not refreshed' }
    Write-Host "PASS: GUI returned in $($watch.ElapsedMilliseconds) ms and streamed background output"
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
