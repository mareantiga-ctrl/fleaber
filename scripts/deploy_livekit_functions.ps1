# Deploy das edge functions LiveKit + cleanup (requer supabase login).
# Uso: .\scripts\deploy_livekit_functions.ps1

$ErrorActionPreference = "Stop"
$ProjectRef = "fxdknzrqjenzqcvnwqqq"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

Write-Host "Deploy livekit-mux-publish..."
npx --yes supabase@2.30.4 functions deploy livekit-mux-publish --project-ref $ProjectRef

Write-Host "Deploy complete-mux-live..."
npx --yes supabase@2.30.4 functions deploy complete-mux-live --project-ref $ProjectRef

Write-Host "Deploy livekit-egress-cleanup..."
npx --yes supabase@2.30.4 functions deploy livekit-egress-cleanup --project-ref $ProjectRef

if (-not $env:LIVEKIT_EGRESS_CLEANUP_SECRET) {
  $env:LIVEKIT_EGRESS_CLEANUP_SECRET = [guid]::NewGuid().ToString("N")
  Write-Host "Gerado LIVEKIT_EGRESS_CLEANUP_SECRET (guarda este valor no Vault SQL): $($env:LIVEKIT_EGRESS_CLEANUP_SECRET)"
}

Write-Host "A definir LIVEKIT_EGRESS_CLEANUP_SECRET no projecto..."
npx --yes supabase@2.30.4 secrets set "LIVEKIT_EGRESS_CLEANUP_SECRET=$($env:LIVEKIT_EGRESS_CLEANUP_SECRET)" --project-ref $ProjectRef

Write-Host "Deploy concluido. Corre supabase/sql/livekit_egress_cleanup_cron_batata.sql no SQL Editor (Vault + cron)."
