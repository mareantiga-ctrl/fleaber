# Hub Live v2 - bateria minima (2 Maestro + T4 manual).
# Uso:
#   powershell -File tool/hub_live_v2_validate.ps1 -Step 01 -SkipInstall
#   powershell -File tool/hub_live_v2_validate.ps1 -Step 02 -SkipInstall
param(
  [string]$SellerDevice = "a698f0de",
  [string]$BuyerDevice = "",
  [Parameter(Mandatory = $true)]
  [ValidateSet("01", "02", "03", "04", "all")]
  [string]$Step,
  [switch]$SkipInstall,
  [switch]$FreshLogin,
  [switch]$FreshLoginAllDevices,
  [string]$ItemCode = "",
  [switch]$ManualConfirm
)

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"
$env:MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED = "true"

$maestroBat = Join-Path $root ".tools\maestro\maestro\bin\maestro.bat"
$adb = "$env:ANDROID_HOME\platform-tools\adb.exe"
$reportDir = Join-Path $root "tool/reports"
$manifestPath = Join-Path $root "tool/test_battery_launcher/hub_live_v2_battery.json"
$stateFile = Join-Path $reportDir "hub_live_v2_run_state.json"
$pauseFile = Join-Path $reportDir "hub_live_v2_pause.json"
$shotDir = Join-Path $reportDir "screenshots/hub_live_v2_active"
New-Item -ItemType Directory -Force -Path $shotDir | Out-Null
$sessionFile = Join-Path $reportDir "hub_live_v2_session.json"
$logFile = Join-Path $reportDir "hub_live_v2_validate.log"

function Read-HubSession {
  if (-not (Test-Path $sessionFile)) {
    return @{ buyer_maestro_pass = $false; a0_pass = $false; last_shot_seller = ""; last_shot_buyer = ""; last_shot_at = "" }
  }
  try {
    $j = Get-Content $sessionFile -Raw -Encoding UTF8 | ConvertFrom-Json
    return @{
      buyer_maestro_pass = [bool]$j.buyer_maestro_pass
      a0_pass            = [bool]$j.a0_pass
      last_shot_seller   = [string]$j.last_shot_seller
      last_shot_buyer    = [string]$j.last_shot_buyer
      last_shot_at       = [string]$j.last_shot_at
    }
  } catch {
    return @{ buyer_maestro_pass = $false; a0_pass = $false; last_shot_seller = ""; last_shot_buyer = ""; last_shot_at = "" }
  }
}

function Write-HubSessionPatch([hashtable]$Patch) {
  $cur = Read-HubSession
  foreach ($k in $Patch.Keys) { $cur[$k] = $Patch[$k] }
  $cur | ConvertTo-Json | Set-Content -Path $sessionFile -Encoding UTF8
}

function Shot-Smart {
  param(
    [string]$Name,
    [string]$Device,
    [switch]$Force
  )
  $sess = Read-HubSession
  $role = if ($Device -eq $BuyerDevice) { "buyer" } else { "seller" }
  $lastKey = if ($role -eq "buyer") { "last_shot_buyer" } else { "last_shot_seller" }
  $lastPath = [string]$sess[$lastKey]
  $lastAt = [string]$sess.last_shot_at
  if (-not $Force -and $lastPath -and (Test-Path $lastPath) -and $lastAt) {
    try {
      $age = (Get-Date).ToUniversalTime() - [datetime]::Parse($lastAt)
      if ($age.TotalMinutes -lt 3 -and $Name -match '^(hlv2_warm|hlv2_manual|hlv2_session)') {
        Log "screenshot reutilizado ($Name): $lastPath"
        return $lastPath
      }
    } catch {}
  }
  $taken = Shot $Name $Device
  $patch = @{ last_shot_at = (Get-Date).ToUniversalTime().ToString("o") }
  $patch[$lastKey] = $taken
  Write-HubSessionPatch $patch
  return $taken
}

if ($BuyerDevice -eq "") {
  $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $BuyerDevice = $manifest.devices.buyer.id
}

function Write-ValidateLogLine([string]$msg) {
  $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
  Write-Host $line
  [System.IO.File]::AppendAllText(
    $logFile,
    $line + [Environment]::NewLine,
    (New-Object System.Text.UTF8Encoding $false)
  )
}

function Log($msg) {
  Write-ValidateLogLine $msg
}

function Shot($name, [string]$Device) {
  $path = Join-Path $shotDir "${name}.png"
  & $adb -s $Device shell screencap -p "/sdcard/hlv2_val.png" 2>$null | Out-Null
  & $adb -s $Device pull "/sdcard/hlv2_val.png" $path 2>$null | Out-Null
  Log "screenshot: $path"
  return $path
}

function Write-Pause($stepDef, $exitCode, [string]$Device, [string]$ItemCode = "") {
  $shot = Shot "FAIL_$($stepDef.Id)" $Device
  $pause = @{
    step = $stepDef.Id
    step_num = $stepDef.Num
    item = $ItemCode
    exit_code = $exitCode
    help_chat = $stepDef.HelpPhone
    screenshot = $shot
    at = (Get-Date).ToUniversalTime().ToString("o")
  }
  $pause | ConvertTo-Json | Set-Content -Path $pauseFile -Encoding UTF8
  Log "PAUSE -> $pauseFile (exit 2)"
  exit 2
}

function Invoke-MaestroFlow([string]$flowRel, [string]$Device, [string]$driverPort) {
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
    "--device", $Device, "--driver-host-port", $driverPort
  ) + $envArgs + @($flowPath)
  Log "maestro [$Device] -> $flowRel"
  & $maestroBat @args 2>&1 | ForEach-Object {
    $raw = "$_".TrimEnd()
    if ($raw.Length -eq 0) { return }
    Write-ValidateLogLine "  $raw"
  }
  return $LASTEXITCODE
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
  param([string]$Device)
  Log "Fresh login: pm clear pt.fleaber.app em $Device"
  & $adb -s $Device shell pm clear pt.fleaber.app 2>&1 | Out-Null
  Start-Sleep -Seconds 3
}

function Invoke-FreshLoginIfNeeded {
  param(
    [hashtable]$StepDef,
    [string]$SellerDevice,
    [string]$BuyerDevice
  )
  if (-not $FreshLogin -and -not $FreshLoginAllDevices) { return }
  $maestroEnv = Read-MaestroEnv
  $sellerEmail = if ($maestroEnv.MAESTRO_SELLER_EMAIL) { $maestroEnv.MAESTRO_SELLER_EMAIL } else { "?" }
  $buyerEmail = if ($maestroEnv.MAESTRO_BUYER_EMAIL) { $maestroEnv.MAESTRO_BUYER_EMAIL } else { "?" }
  Log "Contas teste (.maestro/.env): seller=$sellerEmail | buyer=$buyerEmail | pwd=testeteste"

  if ($FreshLoginAllDevices) {
    if (Test-DeviceOnline $SellerDevice) { Clear-FleaberAppData $SellerDevice }
    if (Test-DeviceOnline $BuyerDevice) { Clear-FleaberAppData $BuyerDevice }
    return
  }
  Clear-FleaberAppData $StepDef.Device
}

function Test-DeviceOnline([string]$Device) {
  if ($Device -eq "chrome") { return $true }
  $out = & $adb devices 2>&1 | Out-String
  return ($out -match [regex]::Escape($Device))
}

$steps = @(
  @{
    Num = "01"
    Id = "seller_studio_or_profile"
    Flow = "hub_live_v2/01_seller_profile_and_live.yaml"
    Device = $SellerDevice
    DriverPort = "7003"
    HelpPhone = "TCL: inicia o directo (studio com badge LIVE). O Redmi valida a vista comprador no passo 02."
    Optional = $false
  },
  @{
    Num = "02"
    Id = "buyer_reservations_bag"
    Flow = "hub_live_v2/02_buyer_reservations_and_bag.yaml"
    Device = $BuyerDevice
    DriverPort = "7002"
    HelpPhone = "Buyer: segue seller ate Ver FleaHub -> Entrar no directo. Toca Reservar se barra vazia."
    Optional = $false
  },
  @{
    Num = "03"
    Id = "t4_ps_demo_chrome"
    Flow = $null
    Device = "chrome"
    DriverPort = ""
    HelpPhone = "Chrome T4: /live?liveId=...&ps_demo=1 - checklist T4. Skip OK."
    Optional = $true
  },
  @{
    Num = "04"
    Id = "chrome_video_smoke"
    Flow = $null
    Device = "chrome"
    DriverPort = ""
    HelpPhone = "Chrome video: https://fleaber.pt/hub-staging-axinoquaa/live - SO se precisares ver stream real. Skip OK."
    Optional = $true
  }
)

$toRun = if ($Step -eq "all") { $steps } else { $steps | Where-Object { $_.Num -eq $Step } }

foreach ($s in $toRun) {
  Log "=== STEP $($s.Id) ==="

  if ($s.Num -eq "03") {
    Log "T4 = manual Chrome (sem Maestro). Ver checklist T4. Skip OK."
    @{ last_pass = $s.Id; note = "manual_chrome_t4"; at = (Get-Date).ToUniversalTime().ToString("o") } |
      ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
    continue
  }

  if ($s.Num -eq "04") {
    Log "Video HLS = manual Chrome OPCIONAL. So se Redmi/TCL nao reproduzem por espaco."
    Log "URL: https://fleaber.pt/hub-staging-axinoquaa/live"
    @{ last_pass = $s.Id; note = "manual_chrome_video_optional"; at = (Get-Date).ToUniversalTime().ToString("o") } |
      ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
    continue
  }

  if (-not (Test-DeviceOnline $s.Device)) {
    Log "ERRO: device $($s.Device) offline"
    exit 3
  }

  if (-not $SkipInstall -and ($s.Num -eq "01" -or $s.Num -eq "02")) {
    $apk = Join-Path $root "build/app/outputs/flutter-apk/app-debug.apk"
    if (Test-Path $apk) {
      Log "install APK $($s.Device)..."
      & $adb -s $s.Device install -r $apk 2>&1 | Out-Null
    }
  }

  Invoke-FreshLoginIfNeeded -StepDef $s -SellerDevice $SellerDevice -BuyerDevice $BuyerDevice

  if ($ManualConfirm) {
    $slug = if ($ItemCode -ne "") { $ItemCode } else { $s.Id }
    $dev = $s.Device
    if ($ItemCode -match '^B') { $dev = $BuyerDevice }
    elseif ($ItemCode -match '^A') { $dev = $SellerDevice }
    if ($dev -ne "chrome" -and -not (Test-DeviceOnline $dev)) {
      Log "ERRO: device $dev offline"
      exit 3
    }
    Log "Confirmacao manual ($slug): screenshot only (sem Maestro)"
    if ($dev -ne "chrome") {
      $shot = Shot-Smart "hlv2_manual_${slug}" $dev
      Log "PASS manual confirm ($slug + screenshot: $shot)"
    } else {
      Log "PASS manual confirm ($slug) - Chrome"
    }
    @{ last_pass = $s.Id; note = "manual_confirm_$slug"; item = $slug; at = (Get-Date).ToUniversalTime().ToString("o") } |
      ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
    if (Test-Path $pauseFile) { Remove-Item $pauseFile -Force }
    continue
  }

  $isA0Warm = ($ItemCode -eq "A0")
  if ($s.Num -eq "01" -and -not $FreshLogin -and -not $FreshLoginAllDevices -and $ItemCode -eq "") {
    Log "ERRO: passo 01 sem ItemCode — no launcher selecciona A0, A1 ou A4 (nao corre A0 por defeito)"
    exit 5
  }
  if ($s.Num -eq "01" -and -not $FreshLogin -and -not $FreshLoginAllDevices -and $isA0Warm) {
    Log "Warm studio A0: confirmado no launcher (sem Maestro - nao relanca a app)"
    Log "Screenshot ADB do ecra actual no TCL..."
    $shot = Shot-Smart "hlv2_warm_studio" $s.Device
    Log "PASS warm studio (manual + screenshot: $shot)"
    Log "Seguinte: B1 no REDMI - Maestro tenta 1x (T1-T6 no mesmo flow)"
    Write-HubSessionPatch @{ a0_pass = $true; last_shot_seller = $shot }
    @{ last_pass = $s.Id; note = "warm_studio_manual"; item = "A0"; screenshot = $shot; at = (Get-Date).ToUniversalTime().ToString("o") } |
      ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
    if (Test-Path $pauseFile) { Remove-Item $pauseFile -Force }
    continue
  }

  if ($s.Num -eq "01" -and -not $FreshLogin -and -not $FreshLoginAllDevices -and $ItemCode -match '^A[14]$') {
    Log "ERRO: $ItemCode precisa NOVO LOGIN marcado no launcher (nao repetir warm A0)"
    exit 4
  }

  $flowRel = $s.Flow
  if ($s.Num -eq "01") {
    if ($FreshLogin) {
      if ($ItemCode -eq "A1") {
        $flowRel = "hub_live_v2/01_seller_profile_t5.yaml"
        Log "A1 (T5): perfil FleaHub apenas — nao entra no directo"
      } elseif ($ItemCode -eq "A4") {
        $flowRel = "hub_live_v2/01_seller_profile_t7.yaml"
        Log "A4 (T7): Gravados no perfil — nao entra no directo"
      } else {
        $flowRel = "hub_live_v2/01_seller_profile_and_live.yaml"
        Log "Modo passo 01: NOVO LOGIN - flow completo (perfil + live via Home)"
      }
    }
  }

  if ($s.Num -eq "02" -and $ItemCode -match '^B[2-4]$') {
    $sess = Read-HubSession
    if ($sess.buyer_maestro_pass -and -not $ManualConfirm) {
      Log "${ItemCode}: B1 ja correu Maestro (T1-T6) - sem relaunch/login"
      Log "Confirma visualmente no Redmi ou usa Prosseguir apos falha"
      $shot = Shot-Smart "hlv2_session_buyer" $BuyerDevice
      Log "PASS $ItemCode (sessao buyer, screenshot: $shot)"
      @{ last_pass = $s.Id; note = "buyer_session_$ItemCode"; item = $ItemCode; screenshot = $shot; at = (Get-Date).ToUniversalTime().ToString("o") } |
        ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
      if (Test-Path $pauseFile) { Remove-Item $pauseFile -Force }
      continue
    }
  }

  if ($s.Num -eq "02" -and $ItemCode -ne "") {
    Log "Teste $ItemCode no Redmi - tentativa Maestro (1a vez automatico)"
  }

  $code = Invoke-MaestroFlow $flowRel $s.Device $s.DriverPort
  if ($code -eq 0) {
    Log "PASS $($s.Id)"
    if ($s.Num -eq "02") {
      Write-HubSessionPatch @{ buyer_maestro_pass = $true }
      Log "Sessao buyer: Maestro OK (T1-T6 no mesmo run - prints Maestro em ~/.maestro/tests/)"
    }
    @{ last_pass = $s.Id; at = (Get-Date).ToUniversalTime().ToString("o") } |
      ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
    if (Test-Path $pauseFile) { Remove-Item $pauseFile -Force }
    continue
  }

  Log "FAIL $($s.Id) exit=$code"
  Log "Maestro falhou - faz este passo TU no telemovel e carrega PROSSEGUIR no launcher"
  if ($s.Optional) {
    Log "SKIP $($s.Id) (opcional)"
    continue
  }
  Write-Pause $s $code $s.Device $ItemCode
}

Log "STEP $Step concluido OK"
exit 0
