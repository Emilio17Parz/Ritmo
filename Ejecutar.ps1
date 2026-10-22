param([string]$DeviceId = '')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
& "$PSScriptRoot\Preparar.ps1"
if ($DeviceId) { & flutter run -d $DeviceId } else { & flutter run }
if ($LASTEXITCODE -ne 0) { throw 'Flutter no pudo ejecutar la app. Revisa el mensaje anterior.' }
