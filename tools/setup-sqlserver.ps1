param([string]$Server = '(localdb)\SnackUP')
$ErrorActionPreference = 'Stop'
$demoRoot = Split-Path -Parent $PSScriptRoot
$demoPrivate = Join-Path $demoRoot '.local\snackup-demo'
$demoPython = Join-Path $demoPrivate 'venv\Scripts\python.exe'
if (!(Test-Path -LiteralPath $demoPython)) {
    & (Join-Path $PSScriptRoot 'local-demo.ps1') -Action Prepare
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $demoPython)) { throw 'No se pudo preparar el backend y Python.' }
}
if ($Server -eq '(localdb)\SnackUP') {
    $localDb = Get-Command SqlLocalDB.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if (!$localDb) {
        foreach ($version in @('170','160','150')) {
            $candidate = Join-Path $env:ProgramFiles "Microsoft SQL Server\$version\Tools\Binn\SqlLocalDB.exe"
            if (Test-Path -LiteralPath $candidate) { $localDb = $candidate; break }
        }
    }
    if (!$localDb) { throw 'Instala SQL Server Express LocalDB de Microsoft antes de continuar.' }
    $instances = & $localDb info
    if ('SnackUP' -notin $instances) {
        & $localDb create SnackUP
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear la instancia SQL Server LocalDB SnackUP.' }
    }
    & $localDb start SnackUP
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo iniciar SQL Server LocalDB SnackUP.' }
}
& $demoPython -m pip install pyodbc==5.3.0
if ($LASTEXITCODE -ne 0) { throw 'No se pudo instalar el conector SQL Server.' }
$configFile = Join-Path $demoPrivate 'database.json'
$previousConfig = if (Test-Path -LiteralPath $configFile) { [IO.File]::ReadAllText($configFile) } else { $null }
try {
    @{engine='sqlserver';server=$Server;database='SnackUP_Local'} | ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding utf8
    Push-Location $demoRoot
    try {
        & $demoPython (Join-Path $PSScriptRoot 'local_demo_backend.py') --init-only
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar SnackUP_Local. Revisa el error de SQL Server anterior.' }
    } finally { Pop-Location }
} catch {
    if ($null -ne $previousConfig) { [IO.File]::WriteAllText($configFile, $previousConfig) }
    else { Remove-Item -LiteralPath $configFile -ErrorAction SilentlyContinue }
    throw
}
Write-Output "Base SQL Server lista: $Server / SnackUP_Local. No se importaron ni modificaron datos de Firebase."
Write-Output 'Reinicia la app con DETENER-SNACKUP-LOCAL.cmd e INICIAR-SNACKUP-LOCAL.cmd.'
