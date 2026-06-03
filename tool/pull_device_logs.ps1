# Copia logs do telemóvel Android para logs/device/ (o Cursor lê daqui).
# Uso: .\tool\pull_device_logs.ps1
# Requer: adb no PATH, USB debugging, app com.mycompany.fleaber instalada.

$ErrorActionPreference = "Stop"

# adb no PATH ou em Android SDK
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  $sdkAdb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
  if (Test-Path $sdkAdb) {
    $env:PATH = "$(Split-Path $sdkAdb -Parent);$env:PATH"
  }
}

$PackageId = "com.mycompany.fleaber"
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$DestDir = Join-Path $ProjectRoot "logs\device"

if (-not (Test-Path $DestDir)) {
  New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
}

function Test-AdbDevice {
  $devices = adb devices 2>&1 | Select-String "device$"
  return ($null -ne $devices -and $devices.Count -gt 0)
}

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  Write-Host "ERRO: adb nao encontrado. Instala Android SDK platform-tools ou abre Android Studio."
  exit 1
}

if (-not (Test-AdbDevice)) {
  Write-Host "ERRO: Nenhum dispositivo ADB. Liga USB + depuracao USB."
  exit 1
}

$ExternalBase = "/sdcard/Android/data/$PackageId/files/fleaber_logs"
$Files = @(
  @{ Remote = "$ExternalBase/fleaber_app.log"; Local = "fleaber_app.log" },
  @{ Remote = "$ExternalBase/fleaber_app_readable.log"; Local = "fleaber_app_readable.log" },
  @{ Remote = "$ExternalBase/live_publish_debug.log"; Local = "live_publish_debug.log" },
  @{ Remote = "$ExternalBase/last_sync.txt"; Local = "last_sync.txt" }
)

$ok = 0
foreach ($f in $Files) {
  $localPath = Join-Path $DestDir $f.Local
  adb pull $f.Remote $localPath 2>$null | Out-Null
  if (Test-Path $localPath) {
    $size = (Get-Item $localPath).Length
    Write-Host "OK  $($f.Local) ($size bytes)"
    $ok++
  } else {
    Write-Host "SKIP $($f.Local) (nao encontrado no telemovel)"
  }
}

# Fallback: pasta interna (run-as) — Documents / app_flutter
$InternalFiles = @(
  "fleaber_app.log",
  "live_publish_debug.log"
)
foreach ($name in $InternalFiles) {
  $localPath = Join-Path $DestDir "${name}.internal"
  $content = adb exec-out "run-as $PackageId cat app_flutter/$name" 2>$null
  if ($LASTEXITCODE -eq 0 -and $content) {
    Set-Content -Path $localPath -Value $content -Encoding UTF8
    Write-Host "OK  $name (via run-as -> ${name}.internal)"
    $ok++
  }
}

$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Set-Content -Path (Join-Path $DestDir "pulled_at.txt") -Value "Pulled: $stamp"
Write-Host ""
Write-Host "Destino: $DestDir"
Write-Host "Ficheiros obtidos: $ok"
if ($ok -eq 0) {
  Write-Host "Dica: abre a app no telemovel, reproduz o problema, volta a correr este script."
  exit 2
}
