param(
    [string]$ApiUrl = 'http://localhost:8001',
    [ValidateRange(1024, 65535)][int]$Puerto = 8000,
    [switch]$SinCompilar,
    [switch]$DemoLocal
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$api = [Uri]$ApiUrl
if ($api.Scheme -notin @('http','https') -or $api.Host -notin @('localhost','127.0.0.1','::1') -or $api.UserInfo -or $api.AbsolutePath -ne '/') {
    throw 'ApiUrl debe ser el origen del backend local, sin credenciales ni ruta /api/v1.'
}
if ($api.Port -eq $Puerto) {
    throw 'La API y el servidor conjunto necesitan puertos diferentes. Consulta ALUMNOS_REST.md.'
}
try {
    $health = Invoke-RestMethod -Uri ($api.AbsoluteUri.TrimEnd('/') + '/health/ready') -TimeoutSec 8
    if ($health.status -ne 'ready') { throw 'La API no indica que esté lista.' }
} catch {
    throw "FastAPI no está disponible en $ApiUrl. El contenedor PostgreSQL por sí solo no inicia la API. Arranca primero el backend con su configuración privada. Consulta ALUMNOS_REST.md."
}
$nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
$node = if ($nodeCommand) { $nodeCommand.Source } else { $null }
if ($node) {
    $nodeVersion = & $node --version
    if ([int]($nodeVersion.TrimStart('v').Split('.')[0]) -lt 18) { $node = $null }
}
if (-not $node) {
    $bundledNode = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
    if (Test-Path -LiteralPath $bundledNode) { $node = $bundledNode }
}
if (-not $node) { throw 'Se necesita Node.js 18 o posterior para el servidor conjunto.' }
Push-Location -LiteralPath $project
try {
    if (-not $SinCompilar) {
        $buildFlags = @('build','web','--release','--no-pub','--no-web-resources-cdn','--pwa-strategy=none')
        if ($DemoLocal) { $buildFlags += '--dart-define=SNACKUP_LOCAL_DEMO=true' }
        & flutter @buildFlags
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar el frontend. Ejecuta flutter pub get y revisa el error anterior.' }
    }
    if (-not (Test-Path -LiteralPath 'build/web/index.html')) { throw 'Falta build/web. Ejecuta el script sin -SinCompilar.' }
    Write-Host "Abre http://localhost:$Puerto y mantén esta terminal abierta."
    Write-Host "El SNACKUP_PUBLIC_ORIGIN del backend debe coincidir con http://localhost:$Puerto."
    & $node tools/serve_students.mjs --port $Puerto --backend ($api.AbsoluteUri.TrimEnd('/'))
} finally {
    Pop-Location
}
