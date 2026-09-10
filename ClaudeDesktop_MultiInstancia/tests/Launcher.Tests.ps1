$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$sourcePath = Join-Path $PSScriptRoot '..\Setup-ClaudeMulti.ps1'
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$null, [ref]$errors)
if ($errors.Count) { throw ($errors.Message -join '; ') }
$assignment = $ast.Find({ param($n)
    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $n.Left.Extent.Text -eq '$script:LauncherPs1'
}, $true)
Invoke-Expression $assignment.Extent.Text
$launcherErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($script:LauncherPs1, [ref]$null, [ref]$launcherErrors)
if ($launcherErrors.Count) { throw ($launcherErrors.Message -join '; ') }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ClaudeMulti-test-' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($testRoot)
$utf8 = New-Object Text.UTF8Encoding($false)
try {
    $stub = Join-Path $testRoot 'Setup stub.ps1'
    $resultPath = Join-Path $testRoot 'result.json'
    $record = "`n`$PSBoundParameters | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath '$($resultPath.Replace("'", "''"))'`n"
    # Exact parameter declarations, but no setup or deletion code.
    $parameterSource = ($ast.ParamBlock.Attributes.Extent.Text -join "`n") + "`n" + $ast.ParamBlock.Extent.Text
    [IO.File]::WriteAllText($stub, $parameterSource + $record, $utf8)
    $ErrorActionPreference = 'SilentlyContinue'
    & powershell.exe -NoProfile -NonInteractive -File $stub -Profiles Cuenta1 Cuenta2 Cuenta3 -PortableDir C:\Example 2>$null
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0) { throw 'Unexpected positional arguments were accepted' }
    Write-Host 'PASS: unnamed extra profiles rejected before any action'

    $oldParams = $parameterSource.Replace(', PositionalBinding = $false', '')
    [IO.File]::WriteAllText($stub, $oldParams + $record, $utf8)
    & powershell.exe -NoProfile -NonInteractive -File $stub -Profiles Cuenta1 Cuenta2 Cuenta3 -PortableDir C:\Example
    $oldResult = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if (-not $oldResult.RemoveProfile) { throw 'Original binding bug not reproduced' }
    Write-Host "PASS: original call assigned RemoveProfile=$($oldResult.RemoveProfile)"

    [IO.File]::WriteAllText($stub, $parameterSource + $record, $utf8)
    $setup = $stub
    $cfg = [pscustomobject]@{
        profiles = @('Cuenta1', 'Trabajo con espacios', "O'Brien", 'Cuenta4') | ForEach-Object { [pscustomobject]@{ name = $_ } }
        portableDir = 'C:\Portable con espacios'
        copyMcp = $true
        sharedMemory = $true
        sharedDir = 'C:\Memoria compartida'
    }
    # Execute the actual payload-building code from the generated launcher.
    $begin = $script:LauncherPs1.IndexOf('        $setupParams =')
    $end = $script:LauncherPs1.IndexOf('        $child = Start-Process', $begin)
    Invoke-Expression $script:LauncherPs1.Substring($begin, $end - $begin)
    & powershell.exe -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand $encodedCommand
    if ($LASTEXITCODE -ne 0) { throw 'Encoded update failed' }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if (($result.Profiles -join '|') -ne (($cfg.profiles.name) -join '|')) { throw 'Profiles changed in transit' }
    if ($result.RemoveProfile -or $result.Revert -or $result.Force) { throw 'Destructive option unexpectedly bound' }
    if ($result.PortableDir -ne $cfg.portableDir -or $result.SharedDir -ne $cfg.sharedDir) { throw 'Paths changed' }
    Write-Host 'PASS: four profiles, spaces, apostrophe and settings transported correctly'
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolved) -like 'ClaudeMulti-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
