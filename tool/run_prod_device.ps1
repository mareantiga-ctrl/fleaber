#Requires -Version 5.1
<#
.SYNOPSIS
  Corre a app Flutter contra Supabase Prod (Stripe Test no projecto).
  Anon: tool/live_ops_production.env ou prompt no terminal (nao no chat).

.EXAMPLE
  powershell -File tool/run_prod_device.ps1
  powershell -File tool/run_prod_device.ps1 -DeviceId JRK7AINR9DIJEQ8P
#>
param(
  [string]$DeviceId = '',
  [switch]$BuildApkOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
  $root = (Get-Location).Path
}
Set-Location $root

$prodRef = 'bpmpkzwnrbmuqnhgdscf'
$prodUrl = "https://$prodRef.supabase.co"
$envFile = Join-Path $PSScriptRoot 'live_ops_production.env'

function Get-EnvValue([string]$path, [string]$key) {
  if (-not (Test-Path $path)) { return '' }
  foreach ($line in Get-Content $path -Encoding UTF8) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $prefix = "$key="
    if ($t.StartsWith($prefix) -or $t.StartsWith("$key =")) {
      $idx = $t.IndexOf('=')
      if ($idx -lt 0) { continue }
      return $t.Substring($idx + 1).Trim().Trim('"').Trim("'")
    }
  }
  return ''
}

$anon = Get-EnvValue $envFile 'SUPABASE_ANON_KEY'
if (-not $anon) { $anon = Get-EnvValue $envFile 'FLEABER_SUPABASE_ANON_KEY' }
$urlFromFile = Get-EnvValue $envFile 'SUPABASE_URL'
if ($urlFromFile) {
  $u = $urlFromFile.TrimEnd('/')
  if ($u.EndsWith('/rest/v1')) { $u = $u.Substring(0, $u.Length - '/rest/v1'.Length) }
  $prodUrl = $u
}

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

if (-not $anon) {
  Write-Host ''
  Write-Host 'Cola a chave anon/public do Prod e Enter:' -ForegroundColor Cyan
  $anon = (Read-Host).Trim()
}

if (-not $anon -or $anon.Length -lt 40) {
  throw 'Anon em falta ou demasiado curta. Guarda SUPABASE_ANON_KEY em tool/live_ops_production.env'
}

$anonRole = Get-JwtRole $anon
if ($anonRole -eq 'service_role') {
  throw 'RECUSADO: SUPABASE_ANON_KEY e service_role. Corre tool/fix_live_ops_production_env_a2.ps1. Nunca embutir service_role no cliente.'
}
if ($anonRole -ne 'anon') {
  throw "RECUSADO: SUPABASE_ANON_KEY role=$anonRole (esperado anon)."
}

if ($anon -match 'fxdknzrqjenzqcvnwqqq') {
  throw 'Essa anon parece de staging. Usa a anon do projecto Prod.'
}

Write-Host "Prod URL: $prodUrl" -ForegroundColor Green
Write-Host "Anon:     ok ($($anon.Length) chars, valor nao impresso)" -ForegroundColor Green

$defines = @(
  '--dart-define=FLEABER_ENV=production',
  "--dart-define=FLEABER_SUPABASE_URL=$prodUrl",
  "--dart-define=FLEABER_SUPABASE_ANON_KEY=$anon"
)

if ($BuildApkOnly) {
  Write-Host 'A compilar APK release Prod...' -ForegroundColor Cyan
  & flutter build apk --release @defines
  exit $LASTEXITCODE
}

$devicesOut = & flutter devices 2>&1 | Out-String
if ($DeviceId) {
  $target = $DeviceId
} elseif ($devicesOut -match 'JRK7AINR9DIJEQ8P') {
  $target = 'JRK7AINR9DIJEQ8P'
} else {
  $m = [regex]::Match($devicesOut, '([A-Z0-9]{10,})\s+\S*\s+android', 'IgnoreCase')
  if (-not $m.Success) {
    $m = [regex]::Match($devicesOut, 'mobile\)\s+.+?\s+([A-Za-z0-9]+)\s+')
  }
  if ($m.Success) { $target = $m.Groups[1].Value } else { $target = '' }
}

if ($devicesOut -match 'not authorized') {
  Write-Host ''
  Write-Host 'TCL ligado mas NAO autorizado. No telemovel: aceita Permitir depuracao USB.' -ForegroundColor Yellow
  Write-Host 'Depois volta a correr este script.' -ForegroundColor Yellow
  exit 2
}

if (-not $target) {
  Write-Host 'Nenhum device Android detectado. Devices:' -ForegroundColor Yellow
  & flutter devices
  exit 3
}

Write-Host "Device: $target" -ForegroundColor Green
Write-Host 'A iniciar flutter run (Prod / Stripe Test no backend)...' -ForegroundColor Cyan
& flutter run -d $target @defines
exit $LASTEXITCODE
