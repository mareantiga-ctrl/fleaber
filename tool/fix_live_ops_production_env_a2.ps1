#Requires -Version 5.1
<#
.SYNOPSIS
  Corrige tool/live_ops_production.env: ANON deve ser role=anon.
  Se SUPABASE_ANON_KEY decodificar como service_role, move para SUPABASE_SERVICE_ROLE_KEY
  e obtem anon real via supabase CLI (nao imprime secrets).
#>
$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$envFile = Join-Path $PSScriptRoot 'live_ops_production.env'
$prodRef = 'bpmpkzwnrbmuqnhgdscf'

function Get-JwtRole([string]$jwt) {
  if (-not $jwt -or $jwt.Length -lt 20) { return 'missing' }
  try {
    $payload = ($jwt.Split('.'))[1]
    $mod = $payload.Length % 4
    if ($mod -eq 2) { $payload += '==' }
    elseif ($mod -eq 3) { $payload += '=' }
    $norm = $payload.Replace('-', '+').Replace('_', '/')
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($norm))
    if ($json -match '"role"\s*:\s*"([^"]+)"') { return $Matches[1] }
  } catch {}
  return 'unknown'
}

function Read-EnvMap([string]$path) {
  $map = @{}
  if (-not (Test-Path $path)) { return $map }
  foreach ($line in Get-Content $path -Encoding UTF8) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $i = $t.IndexOf('=')
    if ($i -lt 1) { continue }
    $k = $t.Substring(0, $i).Trim()
    $v = $t.Substring($i + 1).Trim().Trim('"').Trim("'")
    $map[$k] = $v
  }
  return $map
}

function Get-ProdAnonFromCli {
  $keysFile = Join-Path $RepoRoot 'tool\reports\_tmp_api_keys_fix_a2.json'
  $errFile = Join-Path $RepoRoot 'tool\reports\_tmp_api_keys_fix_a2.err'
  & npx --yes supabase projects api-keys --project-ref $prodRef -o json 1> $keysFile 2> $errFile
  if ($LASTEXITCODE -ne 0) {
    throw ("supabase api-keys falhou (ver " + $errFile + "). Precisas de login CLI.")
  }
  $parsed = Get-Content $keysFile -Raw -Encoding UTF8 | ConvertFrom-Json
  $list = @($parsed)
  if ($list.Count -eq 1 -and ($list[0].PSObject.Properties.Name -contains 'keys')) {
    $list = @($list[0].keys)
  }
  $anon = $null
  foreach ($k in $list) {
    $id = [string]$k.id
    $name = [string]$k.name
    if ($id -eq 'anon' -or $name -eq 'anon') {
      $anon = [string]$k.api_key
      break
    }
  }
  Remove-Item $keysFile, $errFile -Force -ErrorAction SilentlyContinue
  if (-not $anon) { throw 'Anon Prod nao encontrada no CLI.' }
  $role = Get-JwtRole $anon
  if ($role -ne 'anon') { throw ("CLI devolveu role=" + $role + " (esperado anon).") }
  return $anon
}

Write-Host '=== Fix live_ops_production.env (A2) ===' -ForegroundColor Cyan
$map = Read-EnvMap $envFile
$anon = $map['SUPABASE_ANON_KEY']
$svc = $map['SUPABASE_SERVICE_ROLE_KEY']
$anonRole = Get-JwtRole $anon
$svcRole = Get-JwtRole $svc

$anonLen = 0
if ($anon) { $anonLen = $anon.Length }
$svcLen = 0
if ($svc) { $svcLen = $svc.Length }
Write-Host ("  SUPABASE_ANON_KEY role=" + $anonRole + " len=" + $anonLen)
Write-Host ("  SUPABASE_SERVICE_ROLE_KEY role=" + $svcRole + " len=" + $svcLen)

$needsRewrite = $false
$manualRotation = $false

if ($anonRole -eq 'service_role') {
  Write-Host '  MISLABEL: ANON_KEY e service_role - a mover para SERVICE_ROLE_KEY' -ForegroundColor Yellow
  if (-not $svc -or $svcRole -ne 'service_role') {
    $svc = $anon
  }
  $anon = Get-ProdAnonFromCli
  $needsRewrite = $true
  $manualRotation = $true
} elseif ($anonRole -ne 'anon') {
  Write-Host '  ANON em falta ou invalida - a obter via CLI...' -ForegroundColor Yellow
  $anon = Get-ProdAnonFromCli
  $needsRewrite = $true
} else {
  Write-Host '  ANON ja e role=anon' -ForegroundColor Green
}

if ($needsRewrite -or -not (Test-Path $envFile)) {
  $url = $map['SUPABASE_URL']
  if (-not $url) { $url = "https://$prodRef.supabase.co" }
  $lines = @(
    '# Fleaber production ops - GITIGNORED (tool/*.env). NUNCA commit.',
    '# SUPABASE_ANON_KEY = JWT role=anon (cliente/scripts read-only).',
    '# SUPABASE_SERVICE_ROLE_KEY = JWT role=service_role (SO server/ops locais).',
    "FLEABER_PROD_PROJECT_REF=$prodRef",
    "SUPABASE_URL=$url",
    "SUPABASE_ANON_KEY=$anon"
  )
  if ($svc) {
    $lines += "SUPABASE_SERVICE_ROLE_KEY=$svc"
  }
  foreach ($k in @('PROD_TEST_SELLER_EMAIL','PROD_TEST_SELLER_PASSWORD','PROD_TEST_SELLER_ID','PROD_TEST_SELLER_HANDLE','SUPABASE_DB_PASSWORD')) {
    if ($map.ContainsKey($k) -and $map[$k]) {
      $lines += "$k=$($map[$k])"
    }
  }
  Set-Content -Path $envFile -Value ($lines -join "`r`n") -Encoding UTF8
  Write-Host ("  Escrito " + $envFile + " (valores nao impressos)") -ForegroundColor Green
}

$map2 = Read-EnvMap $envFile
$r2 = Get-JwtRole $map2['SUPABASE_ANON_KEY']
if ($r2 -ne 'anon') { throw ("Pos-fix ANON ainda role=" + $r2) }
Write-Host ("  VERIFY SUPABASE_ANON_KEY role=" + $r2 + " OK") -ForegroundColor Green

if ($manualRotation) {
  Write-Host ''
  Write-Host 'MANUAL SECRET ROTATION REQUIRED' -ForegroundColor Red
  Write-Host 'A service_role esteve etiquetada como ANON neste ficheiro local.'
  Write-Host 'Rodar no Dashboard Supabase (projecto Prod): Settings > API > service_role > Reset.'
  Write-Host 'Depois actualizar SUPABASE_SERVICE_ROLE_KEY neste ficheiro e secrets das Edge Functions.'
  Write-Host 'Anon publica (role=anon) NAO precisa rotacao por este incidente.'
}

exit 0
