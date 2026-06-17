# Actualiza registo de testes e gera TEST_BATTERY_LIVE.md (ler apos cada teste).
param(
  [Parameter(Mandatory = $true)]
  [string]$TestId,
  [Parameter(Mandatory = $true)]
  [ValidateSet("PASS", "FAIL", "SKIP", "TODO", "RUNNING", "PENDING", "PASS_COM_AVISO", "PASS_COM_AVISO_DEEPLINK")]
  [string]$Status,
  [string]$Stamp = "",
  [string]$FailReason = "",
  [string]$LogPath = "",
  [string]$UxNote = "",
  [string]$AuditConclusion = "",
  [string]$AuditPath = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $root "tool\test_battery_manifest.json"
$registryPath = Join-Path $root "tool\test_battery_registry.json"
$liveMdPath = Join-Path $root "tool\TEST_BATTERY_LIVE.md"

if (-not (Test-Path $manifestPath)) {
  Write-Error "Falta $manifestPath"
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$testDef = $manifest.tests | Where-Object { $_.id -eq $TestId } | Select-Object -First 1
if (-not $testDef) {
  Write-Error "TestId desconhecido: $TestId"
}

$existing = @()
if (Test-Path $registryPath) {
  $parsed = Get-Content $registryPath -Raw | ConvertFrom-Json
  if ($parsed.results) { $existing = @($parsed.results) }
}

$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$entry = [ordered]@{
  id = $TestId
  name = $testDef.name
  title = $testDef.title
  phase = $testDef.phase
  layer = $testDef.layer
  expected = $testDef.expected
  status = $Status
  stamp = $Stamp
  updatedAt = $now
  failReason = $FailReason
  logPath = $LogPath
  uxNote = $UxNote
}
if ($AuditConclusion -ne "") {
  $entry['auditConclusion'] = $AuditConclusion
}
if ($AuditPath -ne "") {
  $entry['auditPath'] = $AuditPath
}

$merged = @($existing | Where-Object { $_.id -ne $TestId }) + @([pscustomobject]$entry)
$merged = $merged | Sort-Object { $_.id }

$lastStamp = $Stamp
if ($lastStamp -eq "" -and (Test-Path $registryPath)) {
  $prev = Get-Content $registryPath -Raw | ConvertFrom-Json
  if ($prev.lastStamp) { $lastStamp = $prev.lastStamp }
}

$registryOut = [ordered]@{
  version = 1
  updatedAt = $now
  lastStamp = $lastStamp
  results = $merged
}

$registryOut | ConvertTo-Json -Depth 8 | Set-Content -Path $registryPath -Encoding UTF8

$lines = @()
$lines += "# Fleaber - Estado da bateria UX+BD"
$lines += ""
$lines += "Actualizado: **$now** | Ultima corrida: **$lastStamp**"
$lines += ""
$lines += "Regra: **PASS** exige UX Maestro nos emuladores (quando aplicavel) **e** BD. BD sozinho nao conta."
$lines += ""
$lines += "| ID | Fase | Camada | Teste | Esperado | Estado | Motivo falha / nota |"
$lines += "|----|------|--------|-------|----------|--------|---------------------|"

foreach ($t in $manifest.tests) {
  $r = $merged | Where-Object { $_.id -eq $t.id } | Select-Object -First 1
  $st = if ($r -and $r.status) { $r.status } else { "PENDING" }
  $reason = ""
  if ($r) {
    if ($r.failReason) { $reason = [string]$r.failReason }
    elseif ($r.uxNote) { $reason = [string]$r.uxNote }
  }
  $reason = $reason.Replace('|', '/')
  $title = [string]$t.title.Replace('|', '/')
  $exp = [string]$t.expected
  if ($exp.Length -gt 80) { $exp = $exp.Substring(0, 77) + "..." }
  $lines += "| $($t.id) | $($t.phase) | $($t.layer) | $title | $exp | **$st** | $reason |"
}

$lines += ""
$lines += "## Legenda"
$lines += "- **PASS** - auditoria Cursor OK (Maestro + evidência + BD quando aplicável)"
$lines += "- **PASS_COM_AVISO** - fluxo OK com avisos UX/dados menores"
$lines += "- **PASS_COM_AVISO_DEEPLINK** - Maestro OK mas navegação via deep link (não valida UX real)"
$lines += "- **PENDING** - ainda nao corrido nesta sessao"
$lines += "- **RUNNING** - em curso"
$lines += "- **SKIP** - manual ou nao automatizado"
$lines += ""
$lines += "Dados: tool/test_battery_registry.json | logs: tool/logs/"
$lines += ""

$lines -join "`n" | Set-Content -Path $liveMdPath -Encoding UTF8

Write-Host "Registry: $TestId = $Status"
