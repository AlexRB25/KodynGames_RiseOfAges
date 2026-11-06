# Publica una actualización: sube la versión (1.0.1 -> 1.0.2), exporta la web,
# hace commit y push (Render la despliega solo).
# Uso: powershell -File tools/publicar.ps1 "Mensaje del cambio"
param([Parameter(Mandatory = $true)][string]$Mensaje)
$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz
$godot = "C:\Users\AlexR\tools\godot\Godot_v4.7.2-stable_win64_console.exe"

# 1. Subir el último número de la versión en project.godot.
$proj = Get-Content project.godot -Raw -Encoding UTF8
if ($proj -notmatch 'config/version="(\d+)\.(\d+)\.(\d+)"') { throw "No encontré config/version en project.godot" }
$nueva = "$($Matches[1]).$($Matches[2]).$([int]$Matches[3] + 1)"
$proj = $proj -replace 'config/version="[^"]*"', "config/version=""$nueva"""
[IO.File]::WriteAllText("$raiz\project.godot", $proj, (New-Object Text.UTF8Encoding $false))
Write-Host "Versión: V$nueva"

# 2. Exportar la web (Godot escribe avisos en stderr: no deben detener el script).
$ErrorActionPreference = "Continue"
$antes = (Get-Item server/public/jugar/index.pck -ErrorAction SilentlyContinue).LastWriteTime
& $godot --headless --path . --export-release "Web" server/public/jugar/index.html 2>&1 | Out-Null
$despues = (Get-Item server/public/jugar/index.pck -ErrorAction SilentlyContinue).LastWriteTime
if ($null -eq $despues -or $despues -eq $antes) { throw "La exportación web falló" }
$ErrorActionPreference = "Stop"
Remove-Item server/public/jugar/*.import -ErrorAction SilentlyContinue

# 3. Commit y push (git avisa de LF/CRLF en stderr: tampoco debe detenerlo).
$ErrorActionPreference = "Continue"
git add -A 2>&1 | Out-Null
git commit -q -m "V${nueva}: $Mensaje`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -q
git log --oneline -1
