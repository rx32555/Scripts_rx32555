# Cubre lo que se vio en el registro de una ejecucion real:
#   1. el flujo de errores del proceso hijo llega en CLIXML y llenaba el panel
#      de XML y de _x000D_;
#   2. el archivo de registro de la ultima ejecucion.
$ErrorActionPreference = 'Stop'

$sourcePath = Join-Path $PSScriptRoot '..\Setup-ClaudeMulti.ps1'
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$null, [ref]$errors)
if ($errors.Count) { throw ($errors.Message -join '; ') }

foreach ($name in @('ConvertFrom-ChildErrorText', 'Write-RunLog', 'Start-RunLog', 'Get-RunLogPath')) {
    $found = $ast.Find({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq $name
    }, $true)
    if (-not $found) { throw "$name was not found" }
    Invoke-Expression $found.Extent.Text
}

# --- 1. CLIXML -------------------------------------------------------------
$clixml = @'
#< CLIXML
<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04"><Obj S="information" RefId="0"><TN RefId="0"><T>System.Management.Automation.InformationRecord</T></TN><ToString>hola desde Write-Host</ToString></Obj><S S="Error">No se encuentra la ruta_x000D__x000A_</S><S S="Error">    + CategoryInfo : ObjectNotFound_x000D__x000A_</S></Objs>
'@

$decoded = ConvertFrom-ChildErrorText $clixml
if ($decoded -match 'CLIXML' -or $decoded -match '_x000D_' -or $decoded -match '<Objs') {
    throw "CLIXML leaked into the GUI text: $decoded"
}
if ($decoded -match 'hola desde Write-Host') {
    throw 'Information records must not be repeated as errors (stdout already carries them)'
}
if ($decoded -notmatch 'No se encuentra la ruta' -or $decoded -notmatch 'ObjectNotFound') {
    throw "Real error text was lost: $decoded"
}
Write-Host 'PASS: the CLIXML error stream is reduced to its error text'

# Un CLIXML cortado a medias (proceso matado) no puede reventar el lector.
if ((ConvertFrom-ChildErrorText "#< CLIXML`r`n<Objs Version=`"1.1.0.1`"><S S=`"Error`">a") -ne '') {
    throw 'Truncated CLIXML should decode to nothing'
}
# Texto plano (por ejemplo de una herramienta nativa) pasa tal cual.
if ((ConvertFrom-ChildErrorText "npx: command not found`r`n") -ne 'npx: command not found') {
    throw 'Plain stderr text must be preserved'
}
if ((ConvertFrom-ChildErrorText '') -ne '') { throw 'Empty stderr must decode to nothing' }
Write-Host 'PASS: truncated, plain and empty error streams are handled'

# --- 2. Registro de la ultima ejecucion ------------------------------------
$realAppData = $env:APPDATA
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ClaudeMulti-log-test-' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($testRoot)
$env:APPDATA = $testRoot
try {
    $script:LogFile = $null
    Write-RunLog 'esto no debe crear nada'     # sin Start-RunLog no se escribe
    if (Test-Path -LiteralPath (Get-RunLogPath)) { throw 'Write-RunLog wrote before Start-RunLog' }

    Start-RunLog -Mode 'perfiles: Cuenta1, Cuenta dos'
    $logPath = Get-RunLogPath
    if (-not (Test-Path -LiteralPath $logPath)) { throw 'Start-RunLog did not create the log file' }
    Write-RunLog '[ok]   primera linea'
    Write-RunLog '[X]    algo fallo'

    $text = [IO.File]::ReadAllText($logPath, [Text.Encoding]::UTF8)
    foreach ($needle in @('perfiles: Cuenta1, Cuenta dos', 'primera linea', 'algo fallo', $env:COMPUTERNAME)) {
        if ($text -notmatch [regex]::Escape($needle)) { throw "Log is missing '$needle'" }
    }
    if ($text -notmatch '\[\d{2}:\d{2}:\d{2}\] \[ok\]') { throw 'Log lines are missing their timestamp' }

    # La segunda ejecucion reemplaza a la anterior: es "la ultima", no un historial.
    Start-RunLog -Mode 'revertir'
    Write-RunLog 'segunda ejecucion'
    $text2 = [IO.File]::ReadAllText($logPath, [Text.Encoding]::UTF8)
    if ($text2 -match 'primera linea') { throw 'The log kept the previous run instead of replacing it' }
    if ($text2 -notmatch 'segunda ejecucion') { throw 'The second run was not recorded' }
    Write-Host 'PASS: last-run.log is rewritten on every run and keeps timestamps'
}
finally {
    $env:APPDATA = $realAppData
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolved) -like 'ClaudeMulti-log-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
