# Setup completo: deploy + cleanup + cron LiveKit egress
# Requer: npx supabase login (uma vez)

param(
  [switch]$SkipDeploy,
  [string]$CleanupSecret = ""
)

$ErrorActionPreference = "Stop"
$ProjectRef = "fxdknzrqjenzqcvnwqqq"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

if (-not $CleanupSecret) {
  $CleanupSecret = [guid]::NewGuid().ToString("N")
}

Write-Host "=== 1/4 LiveKit API cleanup (local) ===" -ForegroundColor Cyan
Get-Content supabase\.env | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') {
    Set-Item -Path "env:$($matches[1].Trim())" -Value $matches[2].Trim()
  }
}
$env:LIVEKIT_EGRESS_CLEANUP_SECRET = $CleanupSecret
npx --yes deno@2.3.5 run --allow-net --allow-env scripts/run_livekit_cleanup.ts

if (-not $SkipDeploy) {
  Write-Host "`n=== 2/4 Deploy edge functions ===" -ForegroundColor Cyan
  npx --yes supabase@2.30.4 functions deploy livekit-mux-publish --project-ref $ProjectRef
  npx --yes supabase@2.30.4 functions deploy complete-mux-live --project-ref $ProjectRef
  npx --yes supabase@2.30.4 functions deploy livekit-egress-cleanup --project-ref $ProjectRef
  npx --yes supabase@2.30.4 secrets set "LIVEKIT_EGRESS_CLEANUP_SECRET=$CleanupSecret" --project-ref $ProjectRef
} else {
  Write-Host "`n=== 2/4 Deploy ignorado (-SkipDeploy) ===" -ForegroundColor Yellow
}

Write-Host "`n=== 3/4 Segredo cron (guardar no Vault SQL) ===" -ForegroundColor Cyan
Write-Host "LIVEKIT_EGRESS_CLEANUP_SECRET = $CleanupSecret"

Write-Host "`n=== 4/4 SQL no Dashboard (SQL Editor) ===" -ForegroundColor Cyan
Write-Host @"
A) Limpeza única BD:
   supabase/sql/livekit_egress_cleanup_once_batata.sql

B) Vault + cron horário (substituir YOUR_SECRET por $CleanupSecret):
   select vault.create_secret(
     '$CleanupSecret',
     'livekit_egress_cleanup_secret',
     'Auth cron livekit-egress-cleanup'
   );

C) Depois correr:
   supabase/sql/livekit_egress_cleanup_cron_batata.sql

D) Teste manual do cron:
   select public.batata_invoke_livekit_egress_cleanup();
"@

Write-Host "`nConcluido." -ForegroundColor Green
