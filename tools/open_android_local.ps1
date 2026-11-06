#Requires -Version 5.1
<# Open the same localhost origin in Android Chrome, without exposing a LAN port.
   Requires one unlocked Android phone with USB debugging approved on this PC. #>
[CmdletBinding()]
param(
    [string]$AdbPath = 'adb',
    [switch]$Paneles
)
$ErrorActionPreference = 'Stop'
$adb = (Get-Command $AdbPath -CommandType Application -ErrorAction Stop).Source
$origin = 'http://localhost:18080'
if ((Invoke-RestMethod "$origin/health/ready" -TimeoutSec 5).status -ne 'ready') {
    throw 'Primero inicia el servidor local de SnackUP.'
}
$usb = & $adb -d get-state 2>$null
if ($LASTEXITCODE -ne 0 -or $usb -ne 'device') {
    throw 'Conecta un solo Android por USB, desbloquealo y acepta la depuracion para esta computadora.'
}
$mapping = @(& $adb -d reverse --list)
if ($LASTEXITCODE -ne 0) {throw 'No fue posible consultar los puertos USB.'}
$existing = @($mapping | Where-Object {$_ -match '\s+tcp:18080\s+'})
if ($existing.Count -gt 0 -and ($existing.Count -ne 1 -or $existing[0] -notmatch '\s+tcp:18080\s+tcp:18080\s*$')) {
    throw 'El puerto del telefono ya esta asignado a otro servicio; no se cambio.'
}
if ($existing.Count -eq 0) {
    & $adb -d reverse --no-rebind tcp:18080 tcp:18080
    if ($LASTEXITCODE -ne 0) {throw 'No se pudo abrir el tunel USB.'}
}
$target = if ($Paneles) { "$origin/paneles/" } else { "$origin/" }
& $adb -d shell am start -a android.intent.action.VIEW -d $target -p com.android.chrome
if ($LASTEXITCODE -ne 0) {throw 'Abre Chrome en el telefono y escribe la direccion local indicada en la guia.'}
Write-Output "SnackUP solicitado en Chrome del telefono: $target"
