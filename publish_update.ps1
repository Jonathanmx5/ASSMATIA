# Publie une mise à jour d'ASSMATIA (APK + manifeste) sur Firebase Hosting.
# Usage : ./publish_update.ps1 -Notes "Ce qui change"
# Pensez à augmenter "version: X.Y.Z+N" dans pubspec.yaml avant (N doit croître).
param([string]$Notes = "")
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$flutter = "$env:USERPROFILE\flutter\bin\flutter.bat"
$line = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)\+(\d+)').Matches[0]
$version = $line.Groups[1].Value; $build = [int]$line.Groups[2].Value
Write-Host "Construction de la version $version ($build)…"
& $flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "échec de la compilation" }
New-Item -ItemType Directory -Force hosting/update | Out-Null
Get-ChildItem hosting/update -Filter *.apk | Remove-Item
$apk = "assmatia-$version+$build.apk"
Copy-Item build/app/outputs/flutter-apk/app-release.apk "hosting/update/$apk"
@{ version = $version; build = $build; apk = $apk; notes = $Notes } | ConvertTo-Json | Set-Content -Encoding utf8 hosting/update/latest.json
firebase deploy --only hosting --non-interactive
if ($LASTEXITCODE -ne 0) { throw "échec du déploiement" }
Write-Host "Publié : $version ($build)"
