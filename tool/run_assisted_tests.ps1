# Assisted test battery - automation + operator pauses.
# PREFERIR: tool\run_full_automated_battery.ps1 (sem pausas manuais).
# Uso: powershell -ExecutionPolicy Bypass -File tool\run_assisted_tests.ps1 -SkipInstall
param(
  [string]$SellerDevice = "emulator-5554",
  [string]$BuyerDevice = "emulator-5556",
  [switch]$SkipInstall,
  [switch]$SkipMaestro,
  [switch]$SkipFlutterTest,
  [switch]$SkipRegressionGuided
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "C:\src\flutter\bin;C:\Program Files\Git\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$results = New-Object System.Collections.Generic.List[object]

function Record-Result {
  param([string]$Name, [string]$Result, [string]$Note = "")
  $results.Add([pscustomobject]@{ Test = $Name; Result = $Result; Note = $Note }) | Out-Null
}

function Wait-Operator {
  param([string]$Title, [string[]]$Steps)
  Write-Host ""
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host " PAUSA: $Title" -ForegroundColor Cyan
  Write-Host "========================================" -ForegroundColor Cyan
  foreach ($s in $Steps) { Write-Host "  $s" }
  Write-Host ""
  $r = Read-Host "ENTER=continuar | skip=saltar | fail=marcar falha"
  switch ($r.Trim().ToLower()) {
    "skip" { return "skip" }
    "s" { return "skip" }
    "fail" { return "fail" }
    "f" { return "fail" }
    default { return "pass" }
  }
}

function Invoke-TestStep {
  param([string]$Name, [scriptblock]$Action)
  Write-Host ""
  Write-Host ">>> $Name" -ForegroundColor Yellow
  & $Action
  if ($LASTEXITCODE -ne 0) {
    Record-Result $Name "FAIL" "exit $LASTEXITCODE"
    return $false
  }
  Record-Result $Name "PASS" ""
  return $true
}

function Record-Checkpoint {
  param([string]$Name, [string]$OpResult)
  $r = if ($OpResult -eq "pass") { "PASS" } elseif ($OpResult -eq "skip") { "SKIP" } else { "FAIL" }
  Record-Result $Name $r "checkpoint operador"
}

# --- Pre-requisitos ---
$pre = Wait-Operator "Pre-requisitos" @(
  "Emuladores ligados: SELLER=$SellerDevice  BUYER=$BuyerDevice"
  "Confirma flutter devices lista os dois."
  "APK debug compilado ou deixa instalar sem -SkipInstall."
  "tool/live_ops_staging.env e .maestro/.env configurados."
)
if ($pre -eq "skip") { Write-Host "Abortado pelo operador."; exit 0 }
if ($pre -eq "fail") { Record-Result "Pre-requisitos" "FAIL" "" }

Write-Host ""
Write-Host "Dispositivos Flutter:"
flutter devices --device-timeout 5 2>&1

# --- 1. Unit tests ---
if (-not $SkipFlutterTest) {
  $null = Invoke-TestStep "flutter test (suite completa)" { flutter test 2>&1 }
} else {
  Record-Result "flutter test" "SKIP" "-SkipFlutterTest"
}

# --- 2. Staging BD ---
$null = Invoke-TestStep "live_ops_staging_check" { dart run tool/live_ops_staging_check.dart 2>&1 }

# --- 3. Maestro ---
if (-not $SkipMaestro) {
  $maestroArgs = @("-File", "tool\run_maestro_automation.ps1", "-SellerDevice", $SellerDevice, "-BuyerDevice", $BuyerDevice)
  if ($SkipInstall) { $maestroArgs += "-SkipInstall" }
  $null = Invoke-TestStep "run_maestro_automation" { powershell -ExecutionPolicy Bypass @maestroArgs 2>&1 }

  $docArgs = @("-File", "tool\run_doc_apk_tests.ps1", "-Device", $BuyerDevice)
  if ($SkipInstall) { $docArgs += "-SkipInstall" }
  $null = Invoke-TestStep "run_doc_apk_tests" { powershell -ExecutionPolicy Bypass @docArgs 2>&1 }
} else {
  Record-Result "Maestro flows" "SKIP" "-SkipMaestro"
}

# --- 4. Assisted checkpoints ---
Write-Host ""
Write-Host ">>> Checkpoints assistidos" -ForegroundColor Yellow

dart run tool/maestro_prepare_live.dart 2>&1 | Out-Null
$liveId = ""
$envFile = Join-Path $root ".maestro\.env"
if (Test-Path $envFile) {
  $m = Select-String -Path $envFile -Pattern "^MAESTRO_LIVE_ID=(.+)$" | Select-Object -First 1
  if ($m) { $liveId = $m.Matches[0].Groups[1].Value.Trim() }
}

$deepBase = "fleaber://fleaber.com"
$adb = "$env:ANDROID_HOME\platform-tools\adb.exe"

if ($liveId -and (Test-Path $adb)) {
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $link = "$deepBase/maestroSellerStudio?liveId=$liveId" + '&expandCategory=catalog'
  $shellCmd = "am start -W -a android.intent.action.VIEW -d '$link' com.mycompany.fleaber"
  & $adb -s $SellerDevice shell $shellCmd 2>&1 | Out-Null
  $ErrorActionPreference = $prevEap
  Start-Sleep -Seconds 8
}

$r3 = Wait-Operator "Doc 3 - barra Stock vendedor" @(
  "No SELLER ($SellerDevice): studio aberto."
  "Toca Stock no rodape e aumenta qty de artigo vendido."
  "Total e Disp no card devem bater certo com a barra."
)
Record-Checkpoint "Doc 3 APK barra Stock" $r3

$rA3 = Wait-Operator "A3/R32 - qty catalogo" @(
  "1. Quick edit qty no catalogo seller."
  "2. Vende 1 un. na live."
  "3. Termina live e ve gravado."
  "4. Novo directo: Total e Disp iguais no card e carrossel buyer."
)
Record-Checkpoint "A3/R32 alinhamento qty" $rA3

if ($liveId -and (Test-Path $adb)) {
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $linkB = "$deepBase/fleaberLivePlayer?liveId=$liveId" + '&isLive=true'
  $shellCmdB = "am start -W -a android.intent.action.VIEW -d '$linkB' com.mycompany.fleaber"
  & $adb -s $BuyerDevice shell $shellCmdB 2>&1 | Out-Null
  $ErrorActionPreference = $prevEap
  Start-Sleep -Seconds 10
}

$rRifa = Wait-Operator "Rifa comprador" @(
  "No BUYER ($BuyerDevice): player da live com rifa."
  "Confirma Rifa da Live ou Participar na Rifa visivel."
  "Se nao aparecer espera 5s e reabre o player."
)
Record-Checkpoint "Rifa buyer UI" $rRifa

$r7 = Wait-Operator "Doc 7 - Stripe opcional" @(
  "No BUYER: saco com reserva aceite - Pagar - browser Stripe."
  "Cartao teste 4242424242424242."
  "No SELLER: aba Pagamentos mostra valor apos pagamento."
  "skip se nao quiseres pagar agora."
)
Record-Checkpoint "Doc 7 Stripe EUR" $r7

# --- 5. Regression guided ---
if (-not $SkipRegressionGuided) {
  Write-Host ""
  Write-Host ">>> Regression runner --guided" -ForegroundColor Yellow
  $rg = Wait-Operator "Regression matrix guiada" @(
    "Vai correr fleaber_regression_runner --range A080-A130 --guided"
    "Responde aos prompts no terminal."
    "skip para saltar esta fase longa."
  )
  if ($rg -eq "pass") {
    $null = Invoke-TestStep "regression_runner guided A080-A130" {
      dart run tool/fleaber_regression_runner.dart --range A080-A130 --guided 2>&1
    }
  } else {
    Record-Result "regression_runner guided" "SKIP" "operador"
  }
}

# --- Resumo ---
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " RESUMO BATERIA ASSISTIDA" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
$results | Format-Table -AutoSize

$failCount = ($results | Where-Object { $_.Result -eq "FAIL" }).Count
if ($failCount -gt 0) { exit 1 }
exit 0
