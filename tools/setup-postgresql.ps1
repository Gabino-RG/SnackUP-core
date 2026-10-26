$ErrorActionPreference = 'Stop'
$demoRoot = Split-Path -Parent $PSScriptRoot
$demoPython = Join-Path $demoRoot '.local\snackup-demo\venv\Scripts\python.exe'
if (!(Test-Path -LiteralPath $demoPython)) {
    & (Join-Path $PSScriptRoot 'local-demo.ps1') -Action Prepare
    if (!(Test-Path -LiteralPath $demoPython)) { throw 'No se pudo preparar Python.' }
}
& $demoPython -m pip install -r (Join-Path $PSScriptRoot 'requirements-postgresql-local.txt')
if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar el conector de PostgreSQL.' }
& $demoPython (Join-Path $PSScriptRoot 'postgresql_demo.py')
if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar PostgreSQL local.' }
& $demoPython (Join-Path $PSScriptRoot 'local_demo_backend.py') --init-only
if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear el esquema de SnackUP en PostgreSQL.' }
