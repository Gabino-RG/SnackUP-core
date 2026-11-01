$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $project 'backend'
$python = Join-Path $backend '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) { throw 'Falta backend/.venv. Prepara primero el entorno Python.' }
try {
    $ready = Invoke-RestMethod -Uri 'http://localhost:8001/health/ready' -TimeoutSec 3
    if ($ready.status -eq 'ready') { Write-Host 'FastAPI ya está iniciado en http://localhost:8001'; return }
} catch { }
& $python (Join-Path $PSScriptRoot 'sincronizar_docker_local.py')
if ($LASTEXITCODE -ne 0) { throw 'No se pudo verificar la conexión PostgreSQL. No se inicia la API.' }
Push-Location -LiteralPath $backend
try {
    Write-Host 'FastAPI: http://localhost:8001. Mantén esta terminal abierta.'
    & $python -m uvicorn snackup.main:create_app --factory --host 127.0.0.1 --port 8001
} finally { Pop-Location }
