$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $PSScriptRoot '..\Setup-ClaudeMulti.ps1'
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors.Message -join '; ') }
$functionAst = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Stop-PortableProcesses'
}, $true)
if (-not $functionAst) { throw 'Stop-PortableProcesses was not found' }
Invoke-Expression $functionAst.Extent.Text

function Get-I18nStr { param([string]$Key, [object[]]$FormatArgs) "$Key $($FormatArgs -join ' ')" }
function Write-Warn { param([string]$Message) $script:messages += $Message }
function Write-Note { param([string]$Message) $script:messages += $Message }
function Write-Err  { param([string]$Message) $script:messages += $Message }
function Get-PortableProcess { param([string]$PortablePath) @($script:running) }
function Stop-Process {
    param([int]$Id, [switch]$Force, [string]$ErrorAction)
    $script:stopped += $Id
    if ($script:denyStop) { throw 'Access denied' }
    $script:running = @($script:running | Where-Object Id -NE $Id)
}
function Start-Sleep { param([int]$Milliseconds) }

$script:running = @([pscustomobject]@{ Id = 101 }, [pscustomobject]@{ Id = 102 })
$script:stopped = @()
$script:messages = @()
$script:denyStop = $false
if (-not (Stop-PortableProcesses -PortablePath 'C:\ClaudePortable')) { throw 'Closable processes were reported as busy' }
if (($script:stopped -join ',') -ne '101,102') { throw 'Not all portable processes were stopped' }
Write-Host 'PASS: portable processes are closed before replacing the copy'

$script:running = @([pscustomobject]@{ Id = 103 })
$script:stopped = @()
$script:messages = @()
$script:denyStop = $true
if (Stop-PortableProcesses -PortablePath 'C:\ClaudePortable') { throw 'An active process was ignored' }
if (($script:messages -join ' ') -notmatch 'MsgPortableStillBusy') { throw 'Failure was not reported' }
Write-Host 'PASS: a process that remains open blocks the update with an error'

$WhatIfPreference = $true
$script:stopped = @()
if (-not (Stop-PortableProcesses -PortablePath 'C:\ClaudePortable')) { throw 'WhatIf unexpectedly blocked' }
if ($script:stopped.Count -ne 0) { throw 'WhatIf stopped a process' }
Write-Host 'PASS: WhatIf leaves processes running'
