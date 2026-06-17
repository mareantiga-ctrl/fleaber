# Funções partilhadas de auditoria pós-teste.
function Invoke-PostTestAudit {
  param(
    [string]$TestId,
    [string]$Stamp,
    [string]$EvidenceDir = "",
    [string]$LogPath = "",
    [int]$MaestroExit = 0,
    [string]$Layer = "UX",
    [string]$Scenario = ""
  )
  if ($TestId -eq "" -or $Stamp -eq "") { return $null }
  $auditScript = Join-Path $PSScriptRoot "run_post_test_audit.ps1"
  if (-not (Test-Path $auditScript)) { return $null }
  $args = @(
    "-File", $auditScript,
    "-TestId", $TestId,
    "-Stamp", $Stamp,
    "-MaestroExit", "$MaestroExit",
    "-Layer", $Layer
  )
  if ($Scenario -ne "") { $args += @("-Scenario", $Scenario) }
  if ($EvidenceDir -ne "") { $args += @("-EvidenceDir", $EvidenceDir) }
  if ($LogPath -ne "") { $args += @("-LogPath", $LogPath) }
  & powershell -ExecutionPolicy Bypass @args
  $code = $LASTEXITCODE
  $auditRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "tool\logs\audit_$Stamp"
  $resultsFile = Join-Path $auditRoot "audit_results.json"
  $conclusion = ""
  if (Test-Path $resultsFile) {
    try {
      $j = Get-Content $resultsFile -Raw | ConvertFrom-Json
      $v = $j.verdicts | Where-Object { $_.testId -eq $TestId } | Select-Object -First 1
      if ($v) { $conclusion = [string]$v.conclusion }
    } catch {}
  }
  return [pscustomobject]@{
    ExitCode = $code
    Conclusion = $conclusion
    AuditPath = $auditRoot
  }
}

function Update-RegistryFromAudit {
  param(
    [string]$TestId,
    [string]$Stamp,
    [object]$AuditResult,
    [string]$LogPath = "",
    [string]$UxNote = "",
    [string]$FailReason = ""
  )
  if (-not $AuditResult) { return }
  $status = if ($AuditResult.Conclusion) { $AuditResult.Conclusion } else { "FAIL" }
  $reason = $FailReason
  if ($status -eq "FAIL" -and $reason -eq "") { $reason = "auditoria Cursor FAIL" }
  & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "update_test_battery_status.ps1") `
    -TestId $TestId -Status $status -Stamp $Stamp `
    -FailReason:$reason -LogPath $LogPath -UxNote:$UxNote `
    -AuditConclusion $AuditResult.Conclusion -AuditPath $AuditResult.AuditPath | Out-Null
}
