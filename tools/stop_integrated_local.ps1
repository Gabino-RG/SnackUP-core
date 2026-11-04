#Requires -Version 5.1
<#
.SYNOPSIS
Stops the recorded local integration process; PostgreSQL stays up unless selected.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = 'C:/Users/video/Documents/JC/SnackUP-Integracion-Local/config.json',
    [switch]$StopPostgres
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$ConfigPath = [IO.Path]::GetFullPath($ConfigPath)
$runtime = Split-Path -Parent $ConfigPath
$server = Join-Path $PSScriptRoot 'integrated_server.py'
$ownership = Join-Path $runtime 'server-owned.json'
$lock = $null
function Test-ServerCommand($Process) {
    return $Process -and $Process.CommandLine -and
        $Process.CommandLine.Contains('"' + $server + '"') -and
        $Process.CommandLine.Contains('"' + $ConfigPath + '"')
}
try {
    if ((Split-Path -Leaf $ConfigPath) -ne 'config.json' -or
        $runtime.StartsWith($repo + '\', [StringComparison]::OrdinalIgnoreCase) -or $runtime -eq $repo) {
        throw 'ConfigPath debe ser config.json y estar fuera del repositorio.'
    }
    if (-not (Test-Path -LiteralPath $runtime -PathType Container)) { Write-Host 'No existe un entorno local que detener.'; return }
    try { $lock = [IO.File]::Open((Join-Path $runtime 'control.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { throw 'Otro inicio o parada de esta integracion esta en curso.' }
    if (Test-Path -LiteralPath $ownership) {
        try { $record = Get-Content -LiteralPath $ownership -Raw | ConvertFrom-Json }
        catch { throw 'Registro de propiedad invalido; no se detuvo ningun proceso.' }
        if ($record.repo -ne $repo -or $record.script -ne $server -or $record.config -ne $ConfigPath -or $record.port -ne 18080) {
            throw 'El registro no pertenece a esta copia y configuracion; no se detuvo ningun proceso.'
        }
        $owned = Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$record.process_id)"
        if ($owned) {
            if (-not (Test-ServerCommand $owned) -or $owned.ExecutablePath -ne $record.executable -or
                $owned.CreationDate.ToUniversalTime().Ticks -ne ([datetime]$record.created_utc).ToUniversalTime().Ticks) {
                throw 'El PID fue reutilizado o no coincide con su comando/ruta. No se detuvo.'
            }
            # Also handle a failed startup recorded before the venv child bound.
            $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($owned.ProcessId)" |
                Where-Object { Test-ServerCommand $_ })
            foreach ($child in $children) { Stop-Process -Id $child.ProcessId -ErrorAction SilentlyContinue }
            Stop-Process -Id $owned.ProcessId -ErrorAction SilentlyContinue
            Wait-Process -Id $owned.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
            if (Get-CimInstance Win32_Process -Filter "ProcessId=$($owned.ProcessId)") {
                throw 'El proceso no termino; se conserva el registro para revisar su estado.'
            }
            Write-Host 'Servidor integrado detenido. Los datos y los builds se conservan.'
        } else { Write-Host 'El proceso registrado ya habia terminado.' }
        Remove-Item -LiteralPath $ownership
    } else {
        Write-Host 'No hay un proceso propio registrado. No se detiene ningun servidor por numero de puerto.'
    }
    if ($StopPostgres) {
        $cluster = [IO.Path]::GetFullPath((Join-Path $runtime 'postgres-data'))
        $binaries = Join-Path $runtime 'runtime/pgsql/bin'
        $pgctl = Join-Path $binaries 'pg_ctl.exe'
        if (-not $cluster.StartsWith($runtime + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath (Join-Path $cluster 'PG_VERSION') -PathType Leaf) -or
            -not (Test-Path -LiteralPath $pgctl -PathType Leaf)) {
            throw 'No se reconoce el cluster PostgreSQL aislado; no se detuvo.'
        }
        $postgresPidFile = Join-Path $cluster 'postmaster.pid'
        if (-not (Test-Path -LiteralPath $postgresPidFile)) { Write-Host 'PostgreSQL local ya esta detenido.'; return }
        $lines = @(Get-Content -LiteralPath $postgresPidFile)
        if ($lines.Count -lt 4 -or [IO.Path]::GetFullPath($lines[1]) -ne $cluster -or $lines[3] -ne '55432') {
            throw 'El archivo de control no corresponde al cluster y puerto esperados; no se detuvo PostgreSQL.'
        }
        $postgres = Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$lines[0])"
        $expectedExe = [IO.Path]::GetFullPath((Join-Path $binaries 'postgres.exe'))
        if (-not $postgres -or $postgres.ExecutablePath -ne $expectedExe -or
            -not $postgres.CommandLine -or
            -not $postgres.CommandLine.Replace('/', '\').Contains('"' + $cluster + '"')) {
            throw 'El PID de PostgreSQL no coincide con el ejecutable y directorio aislados; no se detuvo.'
        }
        & $pgctl -D $cluster -m fast -w -t 30 stop
        if ($LASTEXITCODE -ne 0) { throw 'pg_ctl no confirmo la parada del cluster local.' }
        Write-Host 'PostgreSQL local detenido limpiamente. No se borraron datos.'
    } else { Write-Host 'PostgreSQL se conserva encendido. Usa -StopPostgres para detener solo el cluster local verificado.' }
} finally {
    if ($lock) { $lock.Dispose() }
}
