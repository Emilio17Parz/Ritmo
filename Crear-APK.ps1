$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
& "$PSScriptRoot\Preparar.ps1"
& flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) { throw 'La compilacion fallo. Comparte el primer error que aparece arriba.' }
Write-Host 'APK para Android moderno:' -ForegroundColor Green
Write-Host "$PSScriptRoot\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
Write-Host 'Tambien se generan APK para ARM de 32 bits y emulador x86_64.'
