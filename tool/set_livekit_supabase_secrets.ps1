# Define secrets LiveKit no Supabase e faz deploy de livekit-mux-publish.
# Lê valores de supabase/.env (não commitar esse ficheiro).
#
# Uso (na raiz do repo):
#   .\tool\set_livekit_supabase_secrets.ps1

param(
  [string]$ProjectRef = "fxdknzrqjenzqcvnwqqq",
  [string]$EnvFile = "supabase\.env"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$envPath = Join-Path $root $EnvFile

if (-not (Test-Path $envPath)) {
  Write-Error "Ficheiro em falta: $envPath — copia supabase/.env.example e preenche LIVEKIT_*"
}

$vars = @{}
Get-Content $envPath | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
  $k, $v = $_ -split '=', 2
  $vars[$k.Trim()] = $v.Trim()
}

foreach ($name in @('LIVEKIT_URL', 'LIVEKIT_API_KEY', 'LIVEKIT_API_SECRET')) {
  if (-not $vars.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($vars[$name])) {
    Write-Error "Em falta em $envPath : $name"
  }
}

Write-Host "Secrets -> projeto $ProjectRef ..."
npx supabase@latest secrets set --project-ref $ProjectRef `
  "LIVEKIT_URL=$($vars['LIVEKIT_URL'])" `
  "LIVEKIT_API_KEY=$($vars['LIVEKIT_API_KEY'])" `
  "LIVEKIT_API_SECRET=$($vars['LIVEKIT_API_SECRET'])"

Write-Host "Deploy livekit-mux-publish ..."
npx supabase@latest functions deploy livekit-mux-publish --project-ref $ProjectRef

Write-Host "OK: https://supabase.com/dashboard/project/$ProjectRef/functions"
