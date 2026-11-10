#Requires -Version 5.1
<#
.SYNOPSIS
  P4.2 - Fail if denylist would be deployed outside staging.

.EXAMPLE
  powershell -File tool/fase4_check_prod_denylist.ps1 -Mode repo
  powershell -File tool/fase4_check_prod_denylist.ps1 -Mode deploy -ProjectRef some-prod-ref
  powershell -File tool/fase4_check_prod_denylist.ps1 -Mode staging-ok -ProjectRef fxdknzrqjenzqcvnwqqq
#>
param(
  [string]$ProjectRef = "",
  [ValidateSet("repo", "deploy", "staging-ok")]
  [string]$Mode = "repo"
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Get-Location).Path
if (-not (Test-Path (Join-Path $RepoRoot "supabase\functions"))) {
  $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$StagingRef = "fxdknzrqjenzqcvnwqqq"
$DeniedEdges = @("delete-test-account", "sec-fase2-e2e-oversell")
$DeniedSqlGlobs = @(
  "supabase\sql\profiles_rls_batata.sql",
  "supabase\sql\sec_025_wallet_party_guard_batata.sql",
  "supabase\sql\sec_025_partial_refund_nested_ensure_batata.sql",
  "supabase\sql\sec_025_ensure_wallet_trigger_hotfix_batata.sql",
  "supabase\sql\live_tips_batata.sql",
  "supabase\sql\sec_blind_p1_contract_qty_pago_batata.sql",
  "supabase\sql\wallets_batata.sql"
)

$violations = New-Object System.Collections.Generic.List[string]

Write-Host ("Fase4 denylist check Mode={0} ProjectRef={1} Root={2}" -f $Mode, $ProjectRef, $RepoRoot)

if ($Mode -eq "deploy") {
  if (-not $ProjectRef) {
    Write-Error "Mode deploy requires -ProjectRef"
    exit 3
  }
  if ($ProjectRef -eq $StagingRef) {
    Write-Host "OK: target is staging; denylist edges allowed with code gates."
    exit 0
  }
  foreach ($e in $DeniedEdges) {
    [void]$violations.Add(("PROD deploy forbidden: edge {0} (project={1})" -f $e, $ProjectRef))
  }
}

if ($Mode -eq "staging-ok") {
  if ($ProjectRef -ne $StagingRef) {
    [void]$violations.Add(("staging-ok only with ref {0} (got {1})" -f $StagingRef, $ProjectRef))
  }
}

$fnDir = Join-Path $RepoRoot "supabase\functions"
if (Test-Path $fnDir) {
  foreach ($e in $DeniedEdges) {
    $path = Join-Path $fnDir $e
    if (Test-Path $path) {
      if (($Mode -eq "deploy") -and ($ProjectRef -ne $StagingRef)) {
        [void]$violations.Add(("Repo has denylist edge {0} - do NOT deploy to prod" -f $e))
      } else {
        Write-Host ("INFO: denylist edge present in repo (staging only): {0}" -f $e)
      }
    }
  }
}

foreach ($rel in $DeniedSqlGlobs) {
  $p = Join-Path $RepoRoot $rel
  if (-not (Test-Path $p)) {
    Write-Host ("WARN: quarantine file missing: {0}" -f $rel)
  } else {
    $head = (Get-Content $p -TotalCount 8 -ErrorAction SilentlyContinue | Out-String)
    if ($head -notmatch "QUARANTIN|quarentena|raise exception") {
      Write-Host ("WARN: {0} missing QUARANTINED marker in header" -f $rel)
    }
  }
}

$sqlDir = Join-Path $RepoRoot "supabase\sql"
if (Test-Path $sqlDir) {
  $n = @(Get-ChildItem $sqlDir -Filter "*.sql").Count
  Write-Host ("INFO: supabase/sql has {0} files - NEVER alphabetical apply on prod" -f $n)
}

if ($violations.Count -gt 0) {
  Write-Host "FAIL:"
  foreach ($v in $violations) { Write-Host (" - {0}" -f $v) }
  exit 2
}

Write-Host "PASS denylist check"
exit 0
