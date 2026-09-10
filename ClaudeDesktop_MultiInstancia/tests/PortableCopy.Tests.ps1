$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $PSScriptRoot '..\Setup-ClaudeMulti.ps1'
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors.Message -join '; ') }
$functionAst = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Copy-ToPortable'
}, $true)
if (-not $functionAst) { throw 'Copy-ToPortable was not found' }
Invoke-Expression $functionAst.Extent.Text

function Get-I18nStr {
    param([string]$Key, [object[]]$Arguments)
    if ($Arguments) { return "$Key $($Arguments -join ' ')" }
    return $Key
}
function Write-Note { param([string]$Message) }

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ClaudeMulti-copy-test-' + [guid]::NewGuid())
$source = Join-Path $testRoot 'source'
$destination = Join-Path $testRoot 'portable'
$badSource = Join-Path $testRoot 'missing-source'
[void][IO.Directory]::CreateDirectory((Join-Path $source 'app'))
[void][IO.Directory]::CreateDirectory((Join-Path $destination 'app'))
[IO.File]::WriteAllText((Join-Path $source 'app\claude.exe'), 'new executable')
[IO.File]::WriteAllText((Join-Path $source 'new.txt'), 'new')
[IO.File]::WriteAllText((Join-Path $destination 'old.txt'), 'old')

try {
    Copy-ToPortable -Source $source -Destination $destination -Overwrite
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'app\claude.exe'))) { throw 'New executable was not activated' }
    if (Test-Path -LiteralPath (Join-Path $destination 'old.txt')) { throw 'Old tree is still active' }
    if (Get-ChildItem -LiteralPath $testRoot -Force | Where-Object Name -Like '.portable.*-*') { throw 'Temporary swap directory was left behind' }
    Write-Host 'PASS: staged copy replaces the previous tree after validation'

    [IO.File]::WriteAllText((Join-Path $destination 'keep.txt'), 'keep me')
    $failed = $false
    try { Copy-ToPortable -Source $badSource -Destination $destination -Overwrite } catch { $failed = $true }
    if (-not $failed) { throw 'Invalid source unexpectedly succeeded' }
    if ((Get-Content -LiteralPath (Join-Path $destination 'keep.txt') -Raw) -ne 'keep me') { throw 'Previous copy was damaged after failed staging' }
    if (Get-ChildItem -LiteralPath $testRoot -Force | Where-Object Name -Like '.portable.staging-*') { throw 'Failed staging directory was left behind' }
    Write-Host 'PASS: failed staging leaves the working copy intact'
}
finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolved) -like 'ClaudeMulti-copy-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
