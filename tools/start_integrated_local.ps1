#Requires -Version 5.1
<#
.SYNOPSIS
Starts only the isolated SnackUP integration environment. No downloads/builds.
Demo data is added only when -SeedDemoData is explicitly supplied.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = 'C:/Users/video/Documents/JC/SnackUP-Integracion-Local/config.json',
    [string]$PythonPath = 'C:/Users/video/Documents/Codex/2026-10-14/h/work/SnackUP-core/backend/.venv/Scripts/python.exe',
    [ValidateRange(15, 180)][int]$StartupTimeoutSeconds = 60,
    [switch]$SeedDemoData
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$ConfigPath = [IO.Path]::GetFullPath($ConfigPath)
$PythonPath = [IO.Path]::GetFullPath($PythonPath)
$runtime = Split-Path -Parent $ConfigPath
$server = Join-Path $PSScriptRoot 'integrated_server.py'
$ownership = Join-Path $runtime 'server-owned.json'
$lock = $null

function Test-ServerCommand($Process) {
    return $Process -and $Process.CommandLine -and
        $Process.CommandLine.Contains('"' + $server + '"') -and
        $Process.CommandLine.Contains('"' + $ConfigPath + '"')
}
function Get-RecordedServer($Record) {
    if ($Record.repo -ne $repo -or $Record.script -ne $server -or
        $Record.config -ne $ConfigPath -or $Record.port -ne 18080) {
        throw 'El registro de proceso no pertenece a esta copia y configuracion.'
    }
    $found = Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$Record.process_id)"
    if (-not $found) { return $null }
    if (-not (Test-ServerCommand $found) -or $found.ExecutablePath -ne $Record.executable -or
        $found.CreationDate.ToUniversalTime().Ticks -ne ([datetime]$Record.created_utc).ToUniversalTime().Ticks) {
        throw 'El PID registrado pertenece ahora a otro proceso; no se modifico.'
    }
    return $found
}
function Save-Ownership($Process, $Launcher) {
    $record = [ordered]@{
        process_id = [int]$Process.ProcessId
        created_utc = $Process.CreationDate.ToUniversalTime().ToString('o')
        executable = $Process.ExecutablePath
        launcher_id = [int]$Launcher.Id
        repo = $repo; script = $server; config = $ConfigPath; port = 18080
    }
    [IO.File]::WriteAllText($ownership, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}
function Get-Listeners {
    return ,@(Get-NetTCPConnection -LocalPort 18080 -State Listen -ErrorAction SilentlyContinue)
}
function Test-Ready {
    try {
        $health = Invoke-RestMethod 'http://localhost:18080/health/ready' -TimeoutSec 3
        $jobs = Invoke-RestMethod 'http://localhost:18080/health/integration' -TimeoutSec 3
        return $health.status -eq 'ready' -and $jobs.status -eq 'ready'
    } catch { return $false }
}
try {
    if ((Split-Path -Leaf $ConfigPath) -ne 'config.json' -or
        $runtime.StartsWith($repo + '\', [StringComparison]::OrdinalIgnoreCase) -or $runtime -eq $repo) {
        throw 'ConfigPath debe ser config.json y estar fuera del repositorio.'
    }
    if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
        throw 'Falta Python con las dependencias del backend. Indica -PythonPath; no se instala automaticamente.'
    }
    $students = Join-Path $repo 'build/web'
    $panels = Join-Path $repo 'app/build/web'
    if (Test-Path -LiteralPath $ConfigPath) {
        try { $settings = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json }
        catch { throw 'config.json no contiene JSON valido; no se muestra su contenido privado.' }
        if ($settings.PSObject.Properties.Name -contains 'students_web') { $students = $settings.students_web }
        if ($settings.PSObject.Properties.Name -contains 'panels_web') { $panels = $settings.panels_web }
    }
    foreach ($build in @(@($students, '/'), @($panels, '/paneles/'))) {
        $index = Join-Path $build[0] 'index.html'
        if (-not (Test-Path -LiteralPath $index -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $build[0] 'flutter_bootstrap.js') -PathType Leaf) -or
            -not ([IO.File]::ReadAllText($index).Contains('<base href="' + $build[1] + '">'))) {
            throw ('Falta el build Flutter con base ' + $build[1] + '. Consulta INTEGRACION_LOCAL.md.')
        }
    }
    New-Item -ItemType Directory -Path $runtime -Force | Out-Null
    try { $lock = [IO.File]::Open((Join-Path $runtime 'control.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { throw 'Otro inicio o parada de esta integracion esta en curso.' }
    if (Test-Path -LiteralPath $ownership) {
        try { $record = Get-Content -LiteralPath $ownership -Raw | ConvertFrom-Json }
        catch { throw 'El registro de propiedad no es valido; no se detuvo ningun proceso.' }
        $existing = Get-RecordedServer $record
        if ($existing) {
            $listeners = Get-Listeners
            if ($listeners.Count -gt 0 -and @($listeners | Where-Object OwningProcess -ne $existing.ProcessId).Count -eq 0 -and (Test-Ready)) {
                Write-Host 'SnackUP ya esta listo: http://localhost:18080/ y http://localhost:18080/paneles/'
                return
            }
            throw 'El proceso propio sigue activo pero no esta listo. Revisa logs o usa stop_integrated_local.ps1.'
        }
        Remove-Item -LiteralPath $ownership
    }
    if ((Get-Listeners).Count -gt 0) { throw 'El puerto 18080 pertenece a un proceso sin registro propio. Se conserva sin cambios.' }
    $logs = Join-Path $runtime 'logs'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    & $PythonPath (Join-Path $PSScriptRoot 'setup_local_postgres.py') --root $runtime
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar PostgreSQL. Consulta los logs externos.' }

    # Credentials stay inside this child, never in command-line arguments/logs.
    $migrationCode = @'
import os, sys
from pathlib import Path
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(sys.argv[2]) / 'tools'))
try:
    from integrated_server import configuration
    cfg = configuration(Path(sys.argv[1]))
    for key in list(os.environ):
        if key.upper().startswith('SNACKUP_'):
            del os.environ[key]
    os.environ.update(SNACKUP_DATABASE_URL=cfg['database_url'],
        SNACKUP_SECRET_KEY=cfg['secret_key'], SNACKUP_ENVIRONMENT='development',
        SNACKUP_PUBLIC_ORIGIN='http://localhost:18080')
    import snackup.config
    original_settings = snackup.config.Settings
    snackup.config.Settings = lambda: original_settings(_env_file=None)
    from alembic.config import Config
    from alembic import command
    command.upgrade(Config(str(Path(sys.argv[2]) / 'backend/alembic.ini')), 'head')
    print('Migraciones locales aplicadas.')
except Exception as error:
    print('Migraciones fallidas: ' + type(error).__name__ + '. No se muestran credenciales.', file=sys.stderr)
    sys.exit(1)
'@
    & $PythonPath -c $migrationCode $ConfigPath $repo
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron aplicar las migraciones locales.' }
    if ($SeedDemoData) {
        & $PythonPath (Join-Path $PSScriptRoot 'seed_integrated.py') --config $ConfigPath
        if ($LASTEXITCODE -ne 0) { throw 'No se pudieron preparar las cuentas sinteticas.' }
    }
    if ((Get-Listeners).Count -gt 0) { throw 'Otro proceso ocupo 18080 durante la preparacion; no se inicia un segundo servidor.' }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $launched = Start-Process -FilePath $PythonPath -ArgumentList ('"{0}" --config "{1}"' -f $server, $ConfigPath) `
        -WorkingDirectory $repo -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $logs "server-$stamp.out.log") `
        -RedirectStandardError (Join-Path $logs "server-$stamp.err.log")
    $initial = Get-CimInstance Win32_Process -Filter "ProcessId=$($launched.Id)"
    if (-not (Test-ServerCommand $initial)) { throw 'El lanzador termino antes de poder registrar su proceso. Revisa los logs externos.' }
    Save-Ownership $initial $launched
    $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $listeners = Get-Listeners
        if ($listeners.Count -gt 0) {
            $owners = @($listeners | Select-Object -ExpandProperty OwningProcess -Unique)
            if ($owners.Count -ne 1) { throw 'Se detectaron procesos distintos en 18080; no se detuvo ninguno.' }
            $actual = Get-CimInstance Win32_Process -Filter "ProcessId=$($owners[0])"
            # Windows venv launchers can spawn the real interpreter as a child.
            if (-not (Test-ServerCommand $actual) -or
                ($actual.ProcessId -ne $launched.Id -and $actual.ParentProcessId -ne $launched.Id)) {
                throw 'El proceso que escucha 18080 no es el lanzador ni un hijo verificado. No se detuvo.'
            }
            Save-Ownership $actual $launched
            if (Test-Ready) {
                Write-Host 'SnackUP listo. Alumnos: http://localhost:18080/ | Cocina/Administracion: http://localhost:18080/paneles/'
                Write-Host ('Logs privados: ' + $logs)
                return
            }
        }
        Start-Sleep -Seconds 2
    }
    throw 'El inicio no alcanzo estado listo. Conserva el PID propio para revisar logs y detenerlo con stop_integrated_local.ps1.'
} finally {
    if ($lock) { $lock.Dispose() }
}
