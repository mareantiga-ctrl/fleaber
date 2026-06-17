# Pausa entre flows Maestro — evita driver timeout e file lock no KeyValueStore.
param(
  [string]$Device = "",
  [int]$Seconds = 8
)

$ErrorActionPreference = "Continue"
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"

Write-Host "Maestro cooldown ${Seconds}s..."
Start-Sleep -Seconds $Seconds

if ($Device -ne "" -and (Test-Path $adb)) {
  & $adb -s $Device shell am force-stop com.mycompany.fleaber 2>&1 | Out-Null
  Start-Sleep -Seconds 2
}

# Dar tempo ao driver Maestro anterior libertar porta/ficheiros
Start-Sleep -Seconds 2
