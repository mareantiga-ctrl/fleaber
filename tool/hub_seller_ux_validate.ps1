# Hub Seller UX — um passo de cada vez; em erro exit 2 → agente pede acao NO CHAT; retoma so apos «feito».
# Ver .cursor/rules/maestro-chat-checkpoint.mdc
# Uso:
#   powershell -File tool/hub_seller_ux_validate.ps1 -Step 01 -SkipInstall
#   powershell -File tool/hub_seller_ux_validate.ps1 -Step 02 -SkipInstall   # retoma sem login
# Estado: tool/reports/hub_ux_run_state.json
param(
  [string]$Device = "a698f0de",
  [Parameter(Mandatory = $true)]
  [ValidateSet("01", "02", "03", "04", "05", "all")]
  [string]$Step,
  [switch]$SkipInstall,
  [switch]$FreshLogin,
  [switch]$FreshLoginAllDevices
)

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"
$env:MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED = "true"

$maestroBat = Join-Path $root ".tools\maestro\maestro\bin\maestro.bat"
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$reportDir = Join-Path $root "tool/reports"
$stateFile = Join-Path $reportDir "hub_ux_run_state.json"
$pauseFile = Join-Path $reportDir "hub_ux_pause.json"
$shotDir = Join-Path $reportDir "screenshots/hub_ux_active"
New-Item -ItemType Directory -Force -Path $shotDir | Out-Null
$logFile = Join-Path $reportDir "hub_seller_ux_validate.log"

function Log($msg) {
  $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
  Write-Host $line
  Add-Content -Path $logFile -Value $line
}

function Shot($name) {
  $path = Join-Path $shotDir "$name.png"
  & $adb -s $Device shell screencap -p "/sdcard/hub_val.png" 2>$null | Out-Null
  & $adb -s $Device pull "/sdcard/hub_val.png" $path 2>$null | Out-Null
  Log "screenshot: $path"
  return $path
}

function Write-Pause($stepDef, $exitCode) {
  $shot = Shot "FAIL_$($stepDef.Id)"
  $pause = @{
    step = $stepDef.Id
    exit_code = $exitCode
    help_chat = $stepDef.HelpChat
    help_phone = $stepDef.HelpPhone
    screenshot = $shot
    at = (Get-Date).ToUniversalTime().ToString("o")
  }
  $pause | ConvertTo-Json | Set-Content -Path $pauseFile -Encoding UTF8
  Log "PAUSE -> $pauseFile (exit 2 = aguarda utilizador no chat)"
  exit 2
}

function Read-MaestroEnv {
  $map = @{}
  $envPath = Join-Path $root ".maestro\.env"
  if (-not (Test-Path $envPath)) { return $map }
  Get-Content $envPath | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $i = $line.IndexOf("=")
    if ($i -lt 1) { return }
    $map[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim()
  }
  return $map
}

function Clear-FleaberAppData {
  Log "Fresh login: pm clear pt.fleaber.app em $Device"
  & $adb -s $Device shell pm clear pt.fleaber.app 2>&1 | Out-Null
  Start-Sleep -Seconds 3
}

function Invoke-FreshLoginIfNeeded {
  if (-not $FreshLogin -and -not $FreshLoginAllDevices) { return }
  $maestroEnv = Read-MaestroEnv
  $sellerEmail = if ($maestroEnv.MAESTRO_SELLER_EMAIL) { $maestroEnv.MAESTRO_SELLER_EMAIL } else { "?" }
  Log "Conta teste seller: $sellerEmail | pwd=testeteste"
  Clear-FleaberAppData
}

function Invoke-MaestroFlow([string]$flowRel) {
  $flowPath = Join-Path $root ".maestro\flows\$flowRel"
  $envArgs = @()
  Get-Content (Join-Path $root ".maestro\.env") | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $i = $line.IndexOf("=")
    if ($i -lt 1) { return }
    $envArgs += "-e"
    $envArgs += "$($line.Substring(0,$i).Trim())=$($line.Substring($i+1).Trim())"
  }
  $args = @(
    "test", "--config", (Join-Path $root ".maestro\config.yaml"),
    "--device", $Device, "--driver-host-port", "7003"
  ) + $envArgs + @($flowPath)
  Log "maestro -> $flowRel"
  & $maestroBat @args 2>&1 | Tee-Object -FilePath $logFile -Append | Out-Host
  return $LASTEXITCODE
}

# Verificar device
$devList = & $adb devices 2>&1 | Out-String
if ($devList -notmatch $Device) {
  Log "ERRO: device $Device nao ligado. Liga USB TCL e activa depuracao."
  exit 3
}

if (-not $SkipInstall) {
  $apk = Join-Path $root "build/app/outputs/flutter-apk/app-debug.apk"
  if (Test-Path $apk) {
    Log "install APK..."
    & $adb -s $Device install -r $apk 2>&1 | Out-Null
  }
}

$steps = @(
  @{
    Num = "01"
    Id = "01_warm_session"
    Flow = "hub_ux/01_warm_session.yaml"
    HelpChat = "No TCL: abre Fleaber. Se estiver no login, entra axinoquaa@axinoquaa.pt / testeteste e espera o tab Inicio. Responde 'feito' quando la estiveres."
    HelpPhone = "Login so se aparecer ecra E-mail. Senao deixa estar."
  },
  @{
    Num = "02"
    Id = "02_perfil_seller"
    Flow = "hub_ux/02_perfil_seller.yaml"
    HelpChat = "Tab Perfil -> cartao anuncios e diretos. Deve aparecer linha FleaHub. Responde 'feito'."
    HelpPhone = "Perfil -> cartao anuncios e diretos"
  },
  @{
    Num = "03"
    Id = "03_definicoes"
    Flow = "hub_ux/03_definicoes.yaml"
    HelpChat = "Perfil -> Definicoes de conta -> scroll ate 'Link publico (Hub)'. Responde 'feito'."
    HelpPhone = "Definicoes, scroll para Hub"
  },
  @{
    Num = "04"
    Id = "04_preparar_directo"
    Flow = "hub_ux/04_preparar_directo.yaml"
    HelpChat = "Home (tab Inicio): espera o feed carregar (spinner desaparece). Toca FAB + (centro) -> Novo Directo -> ecrã «Artigos do directo» com cartão Hub no topo. Responde «feito»."
    HelpPhone = "Inicio: FAB + -> Novo Directo (quando feed visível)"
  },
  @{
    Num = "05"
    Id = "05_live_studio"
    Flow = "hub_ux/05_live_studio.yaml"
    Optional = $true
    HelpChat = "Opcional: so se tiveres live Maestro activa. Perfil -> Painel operacional. Senao responde 'skip'."
    HelpPhone = "Painel operacional (opcional)"
  }
)

$toRun = if ($Step -eq "all") { $steps } else { $steps | Where-Object { $_.Num -eq $Step } }

foreach ($s in $toRun) {
  Log "=== STEP $($s.Id) ==="
  Invoke-FreshLoginIfNeeded
  $code = Invoke-MaestroFlow $s.Flow
  if ($code -eq 0) {
    Log "PASS $($s.Id)"
    @{ last_pass = $s.Id; at = (Get-Date).ToUniversalTime().ToString("o") } |
      ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
    if (Test-Path $pauseFile) { Remove-Item $pauseFile -Force }
    continue
  }
  Log "FAIL $($s.Id) exit=$code"
  if ($s.Optional) {
    Log "SKIP $($s.Id) (opcional)"
    continue
  }
  Write-Pause $s $code
}

Log "STEP $Step concluido OK"
exit 0
