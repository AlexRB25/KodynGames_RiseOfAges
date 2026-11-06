# Compila el APK de Android con la versión actual de project.godot.
# Uso: powershell -File tools/compilar_apk.ps1
# Sale en build/android/RiseOfAges-V<versión>.apk (firmado con la llave de prueba de Godot).
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz
$godot = "C:\Users\AlexR\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
$proj = Get-Content project.godot -Raw -Encoding UTF8
if ($proj -notmatch 'config/version="(\d+)\.(\d+)\.(\d+)"') { throw "No encontré config/version" }
$ver = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
$code = [int]$Matches[1] * 10000 + [int]$Matches[2] * 1000 + [int]$Matches[3]
$p = Get-Content export_presets.cfg -Raw -Encoding UTF8
$p = $p -replace 'version/code=\d+', "version/code=$code" -replace 'version/name="[^"]*"', "version/name=""$ver"""
[IO.File]::WriteAllText("$raiz\export_presets.cfg", $p, (New-Object Text.UTF8Encoding $false))
New-Item -ItemType Directory -Force build/android | Out-Null
$apk = "build/android/RiseOfAges-V$ver.apk"
& $godot --headless --path . --export-debug "Android" $apk 2>&1 | Select-String -Pattern "ERROR|error" | ForEach-Object { $_.Line }
if (Test-Path $apk) { Write-Host "APK: $raiz\$apk ($([math]::Round((Get-Item $apk).Length / 1MB, 1)) MB)" } else { throw "No se generó el APK" }
