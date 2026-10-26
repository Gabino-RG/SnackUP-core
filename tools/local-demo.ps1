param([ValidateSet('Start','Stop','Deliver','Prepare')][string]$Action = 'Start')
$ErrorActionPreference = 'Stop'
$demoRoot = Split-Path -Parent $PSScriptRoot
$demoPrivate = Join-Path $demoRoot '.local\snackup-demo'
$demoPython = Join-Path $demoPrivate 'venv\Scripts\python.exe'
$demoBackend = Join-Path $demoPrivate 'source\backend\snackup\main.py'
$demoStateFile = Join-Path $demoPrivate 'processes.json'
New-Item -ItemType Directory -Path $demoPrivate -Force | Out-Null
function Quote-DemoArgument([string]$Value) { return '"' + $Value + '"' }
function Test-DemoUrl([string]$Url) {
    try { return (Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 3).StatusCode -eq 200 } catch { return $false }
}
function Resolve-DemoRuntime([string]$Name, [string]$Fallback, [int]$Minimum) {
    $paths = @((Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source), $Fallback)
    foreach ($candidate in $paths) {
        if (!$candidate -or !(Test-Path -LiteralPath $candidate)) { continue }
        try {
            if ($Name -eq 'node') { $version = & $candidate -p 'parseInt(process.versions.node)' }
            else { $version = & $candidate -c 'import sys; print(sys.version_info.major * 100 + sys.version_info.minor)' }
            if ($LASTEXITCODE -eq 0 -and [int]$version -ge $Minimum) { return $candidate }
        } catch { }
    }
    throw "No se encontro un runtime compatible: $Name."
}
function Assert-DemoPort([int]$Port, [string]$Script) {
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
    foreach ($listener in $listeners) {
        $owner = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)" -ErrorAction SilentlyContinue
        if (!$owner -or !$owner.CommandLine -or !$owner.CommandLine.Contains($Script)) {
            throw "El puerto $Port esta ocupado por otro servicio. No se modifico ni se detuvo ese servicio."
        }
    }
}
if ($Action -eq 'Stop') {
    # A venv launcher can spawn a child Python process that owns the port.
    # Stop only listeners whose command line names our exact script.
    foreach ($service in @(@{port=8000;script=(Join-Path $PSScriptRoot 'local_demo_backend.py')}, @{port=8080;script=(Join-Path $PSScriptRoot 'serve_api_web.mjs')})) {
        foreach ($listener in @(Get-NetTCPConnection -State Listen -LocalPort $service.port -ErrorAction SilentlyContinue)) {
            $owner = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)" -ErrorAction SilentlyContinue
            if ($owner -and $owner.CommandLine -and $owner.CommandLine.Contains($service.script)) {
                Stop-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
            }
        }
    }
    if (Test-Path -LiteralPath $demoStateFile) {
        $state = Get-Content -Raw -LiteralPath $demoStateFile | ConvertFrom-Json
        foreach ($entry in $state.processes) {
            $process = Get-CimInstance Win32_Process -Filter "ProcessId = $($entry.id)" -ErrorAction SilentlyContinue
            if ($process -and $process.CommandLine -and $process.CommandLine.Contains($entry.script)) {
                Stop-Process -Id $entry.id -ErrorAction SilentlyContinue
            }
        }
        Remove-Item -LiteralPath $demoStateFile -Force
    }
    Write-Output 'SnackUP local detenido. Los pedidos locales se conservan.'
    exit 0
}
if ($Action -eq 'Deliver') {
    if (!(Test-Path -LiteralPath $demoPython)) { throw 'Primero inicia SnackUP local.' }
    Assert-DemoPort 8000 (Join-Path $PSScriptRoot 'local_demo_backend.py')
    & $demoPython (Join-Path $PSScriptRoot 'local_demo_backend.py') --complete-last
    exit $LASTEXITCODE
}
$pythonFallback = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$nodeFallback = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
if (!(Test-Path -LiteralPath $demoBackend)) {
    $archive = Join-Path $demoPrivate 'backend.zip'
    & git -C $demoRoot archive --format=zip -o $archive 1c3459bfd58a083acf4a1638c5013db93873f057 backend
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar la copia local del backend.' }
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $demoPrivate 'source') -Force
}
if (!(Test-Path -LiteralPath $demoPython)) {
    $basePython = Resolve-DemoRuntime 'python' $pythonFallback 311
    & $basePython -m venv (Join-Path $demoPrivate 'venv')
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar Python local.' }
}
$dependencyMarker = Join-Path $demoPrivate 'dependencies-ready.txt'
if (!(Test-Path -LiteralPath $dependencyMarker)) {
    & $demoPython -m pip install -r (Join-Path $demoPrivate 'source\backend\requirements.lock')
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron preparar las dependencias del backend.' }
    Set-Content -LiteralPath $dependencyMarker -Value 'backend 1c3459b' -Encoding utf8
}
if (Test-Path -LiteralPath (Join-Path $demoPrivate 'database.json')) {
    $sqlConfig = Get-Content -Raw (Join-Path $demoPrivate 'database.json') | ConvertFrom-Json
    if ($sqlConfig.engine -eq 'postgresql') {
        & $demoPython (Join-Path $PSScriptRoot 'postgresql_demo.py')
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo iniciar PostgreSQL de SnackUP.' }
    }
    if ($sqlConfig.engine -eq 'sqlserver') {
    & $demoPython -c 'import pyodbc' 2>$null
    if ($LASTEXITCODE -ne 0) {
        & $demoPython -m pip install pyodbc==5.3.0
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar el conector de SQL Server.' }
    }
    if ($sqlConfig.server -eq '(localdb)\SnackUP') {
        $sqlLocalDb = Get-Command SqlLocalDB.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
        if (!$sqlLocalDb) {
            foreach ($version in @('170','160','150')) {
                $candidate = Join-Path $env:ProgramFiles "Microsoft SQL Server\$version\Tools\Binn\SqlLocalDB.exe"
                if (Test-Path -LiteralPath $candidate) { $sqlLocalDb = $candidate; break }
            }
        }
        if (!$sqlLocalDb) { throw 'No se encontro SQL Server LocalDB.' }
        & $sqlLocalDb start SnackUP
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo iniciar SQL Server LocalDB SnackUP.' }
    }
    }
}
if (!(Test-Path -LiteralPath (Join-Path $demoRoot 'build\web\index.html'))) {
    & flutter build web --pwa-strategy=none --no-web-resources-cdn
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar el cliente web.' }
}
$node = Resolve-DemoRuntime 'node' $nodeFallback 20
if ($Action -eq 'Prepare') {
    Write-Output 'Dependencias y cliente web preparados; no se iniciaron servicios ni se creo una base SQLite.'
    exit 0
}
$processes = @()
if (Test-Path -LiteralPath $demoStateFile) { $processes = @((Get-Content -Raw $demoStateFile | ConvertFrom-Json).processes) }
$backendScript = Join-Path $PSScriptRoot 'local_demo_backend.py'
$proxyScript = Join-Path $PSScriptRoot 'serve_api_web.mjs'
Assert-DemoPort 8000 $backendScript
Assert-DemoPort 8080 $proxyScript
if (!(Test-DemoUrl 'http://localhost:8000/health/live')) {
    $process = Start-Process -FilePath $demoPython -ArgumentList (Quote-DemoArgument $backendScript) -WorkingDirectory $demoRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $demoPrivate 'backend.out.log') -RedirectStandardError (Join-Path $demoPrivate 'backend.err.log')
    $processes += @{id=$process.Id;script=$backendScript}
}
for ($attempt=0; $attempt -lt 30; $attempt++) { if (Test-DemoUrl 'http://localhost:8000/health/live') { break }; Start-Sleep -Seconds 1 }
if (!(Test-DemoUrl 'http://localhost:8000/health/live')) { throw "No inicio el backend. Revisa $demoPrivate\backend.err.log" }
if (!(Test-DemoUrl 'http://127.0.0.1:8080/')) {
    $arguments = (Quote-DemoArgument $proxyScript) + ' --backend=http://127.0.0.1:8000 --port=8080'
    $process = Start-Process -FilePath $node -ArgumentList $arguments -WorkingDirectory $demoRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $demoPrivate 'web.out.log') -RedirectStandardError (Join-Path $demoPrivate 'web.err.log')
    $processes += @{id=$process.Id;script=$proxyScript}
}
@{processes=$processes} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $demoStateFile -Encoding utf8
for ($attempt=0; $attempt -lt 15; $attempt++) { if (Test-DemoUrl 'http://127.0.0.1:8080/') { break }; Start-Sleep -Seconds 1 }
if (!(Test-DemoUrl 'http://127.0.0.1:8080/')) { throw "No inicio la app. Revisa $demoPrivate\web.err.log" }
Assert-DemoPort 8000 $backendScript
Assert-DemoPort 8080 $proxyScript
Write-Output 'SnackUP local listo en http://localhost:8080'
Write-Output "El acceso de demostracion esta en $demoPrivate\ACCESO-LOCAL.txt"


