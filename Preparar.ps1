$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter no esta en PATH.' }
& flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron resolver las dependencias.' }
& flutter analyze --no-fatal-infos
if ($LASTEXITCODE -ne 0) { throw 'El analisis encontro errores o advertencias. Comparte la salida.' }
& flutter test
if ($LASTEXITCODE -ne 0) { throw 'Las pruebas fallaron. Comparte la salida.' }
Write-Host 'Ritmo listo para compilar.' -ForegroundColor Green
