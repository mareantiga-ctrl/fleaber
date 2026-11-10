#Requires -Version 5.1
<#
.SYNOPSIS
  Build site fleaber.pt + Hub web Prod (hash URLs) → pasta FTP completa.
  Usa anon real do projecto (CLI). Recusa service_role no cliente.
#>
$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $RepoRoot

$prodRef = 'bpmpkzwnrbmuqnhgdscf'
$prodUrl = "https://$prodRef.supabase.co"
$Website = Join-Path $RepoRoot 'website'
$Out = Join-Path $RepoRoot 'deploy\fleaber_pt'
$HubOut = Join-Path $Out 'fleahub'
$FlutterBuild = Join-Path $RepoRoot 'build\web'
$FtpStamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$FtpPack = Join-Path $RepoRoot "tool\reports\fase4_execution_2026-09-13\P4.5\FTP_FLEABER_PT_PROD_COMPLETO_$FtpStamp"

function Get-JwtRole([string]$jwt) {
  $payload = ($jwt.Split('.'))[1]
  $mod = $payload.Length % 4
  if ($mod -eq 2) { $payload += '==' }
  elseif ($mod -eq 3) { $payload += '=' }
  $norm = $payload.Replace('-', '+').Replace('_', '/')
  $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($norm))
  if ($json -match '"role"\s*:\s*"([^"]+)"') { return $Matches[1] }
  return 'unknown'
}

Write-Host '=== FTP fleaber.pt Prod (Hub layout desktop + hash URLs) ===' -ForegroundColor Cyan

Write-Host '[0/5] Obter anon Prod via supabase CLI (nao imprime o valor)...' -ForegroundColor Yellow
$keysFile = Join-Path $RepoRoot 'tool\reports\_tmp_api_keys_build.json'
$errFile = Join-Path $RepoRoot 'tool\reports\_tmp_api_keys_build.err'
& npx --yes supabase projects api-keys --project-ref $prodRef -o json 1> $keysFile 2> $errFile
if ($LASTEXITCODE -ne 0) {
  throw ("supabase api-keys falhou. Ver: " + $errFile)
}

$anon = $null
$parsed = Get-Content $keysFile -Raw -Encoding UTF8 | ConvertFrom-Json
$list = @($parsed)
# Formato antigo { keys: [...] } ou array directo
if ($list.Count -eq 1 -and ($list[0].PSObject.Properties.Name -contains 'keys')) {
  $list = @($list[0].keys)
}
foreach ($k in $list) {
  $id = [string]$k.id
  $name = [string]$k.name
  if ($id -eq 'anon' -or $name -eq 'anon') {
    $anon = [string]$k.api_key
    break
  }
}
Remove-Item $keysFile -Force -ErrorAction SilentlyContinue
Remove-Item $errFile -Force -ErrorAction SilentlyContinue


if (-not $anon -or $anon.Length -lt 40) {
  throw 'Anon Prod em falta no CLI.'
}
$role = Get-JwtRole $anon
if ($role -ne 'anon') {
  throw "A chave obtida nao e anon (role=$role). Abortar - nunca embutir service_role no web."
}
Write-Host "  OK anon role=$role len=$($anon.Length)" -ForegroundColor Green

# Aviso: env local mal etiquetado — agora falha se algum script tentar usar essa ANON
$envFile = Join-Path $RepoRoot 'tool\live_ops_production.env'
if (Test-Path $envFile) {
  foreach ($line in Get-Content $envFile) {
    if ($line -match '^SUPABASE_ANON_KEY=(.+)$') {
      $envRole = Get-JwtRole $Matches[1].Trim()
      if ($envRole -eq 'service_role') {
        throw 'tool/live_ops_production.env tem SUPABASE_ANON_KEY=service_role. Corre tool/fix_live_ops_production_env_a2.ps1 antes de builds.'
      }
      break
    }
  }
}

Write-Host '[1/5] flutter build web Prod (hash + base-href /fleahub/)...' -ForegroundColor Yellow
& flutter build web --release `
  --base-href=/fleahub/ `
  --dart-define=FLEABER_WEB_HASH_URL=true `
  --dart-define=FLEABER_PUBLIC_REGISTRATION=true `
  --dart-define=FLEABER_ENV=production `
  --dart-define=FLEABER_SUPABASE_URL=$prodUrl `
  --dart-define=FLEABER_SUPABASE_ANON_KEY=$anon
if ($LASTEXITCODE -ne 0) { throw 'flutter build web falhou' }

Write-Host '[2/5] Montar deploy\fleaber_pt ...' -ForegroundColor Yellow
if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item -ItemType Directory -Path $HubOut -Force | Out-Null
Copy-Item -Path (Join-Path $FlutterBuild '*') -Destination $HubOut -Recurse -Force
Copy-Item -Path (Join-Path $Website '*') -Destination $Out -Recurse -Force
$HubIndex = Join-Path $HubOut 'index.html'
if (Test-Path $HubIndex) {
  Copy-Item -Path $HubIndex -Destination (Join-Path $Out 'flutter_app.html') -Force
}

# .htaccess se existir no pack anterior / deploy
$HtSrc = Join-Path $RepoRoot 'deploy\fleaber_pt\.htaccess'
# already wiped - copy from website or known good
$HtKnown = Join-Path $RepoRoot 'tool\reports\fase4_execution_2026-09-13\P4.5\FTP_FLEABER_PT_PROD_COMPLETO\.htaccess'
if ((Test-Path $HtKnown) -and -not (Test-Path (Join-Path $Out '.htaccess'))) {
  Copy-Item $HtKnown (Join-Path $Out '.htaccess') -Force
}

Write-Host '[3/5] Copiar pacote FTP carimbado...' -ForegroundColor Yellow
New-Item -ItemType Directory -Path (Split-Path $FtpPack -Parent) -Force | Out-Null
if (Test-Path $FtpPack) { Remove-Item $FtpPack -Recurse -Force }
Copy-Item -Path $Out -Destination $FtpPack -Recurse -Force

$Readme = @"
FLEABER.PT - FTP COMPLETO (Prod) - LAYOUT DESKTOP HUB + LOGIN
=============================================================
Gerado: $(Get-Date -Format 'yyyy-MM-dd HH:mm')

UPLOAD:
  1. Backup do alojamento (opcional mas recomendado)
  2. Apaga TUDO na pasta publica do dominio
  3. Envia TODO o conteudo DESTA pasta para a raiz (inclui fleahub/)

Build:
  - FLEABER_ENV=production + URL Prod
  - FLEABER_WEB_HASH_URL=true
  - base-href=/fleahub/
  - Hub content width desktop 720/840 (telemovel igual)
  - Login centrado no desktop

Testes:
  https://fleaber.pt/
  https://fleaber.pt/fleahub/index.html#/fleahub
  https://fleaber.pt/fleahub/index.html#/login  (ou Entrar -> Facebook)

NAO abrir LEIA-ME / nginx no Notepad se ja tiveres janelas antigas - fecha-as primeiro.
"@
Set-Content -Path (Join-Path $Out 'LEIA-ME-DEPLOY.txt') -Value $Readme -Encoding UTF8
Set-Content -Path (Join-Path $FtpPack 'LEIA-ME-FTP-PROD.txt') -Value $Readme -Encoding UTF8

Write-Host '[4/5] Verificar main.dart.js...' -ForegroundColor Yellow
$mainJs = Join-Path $HubOut 'main.dart.js'
if (-not (Test-Path $mainJs)) { throw 'main.dart.js em falta' }
$sz = [math]::Round((Get-Item $mainJs).Length / 1MB, 1)
Write-Host ("  OK fleahub\main.dart.js (" + $sz + " MB)") -ForegroundColor Green

Write-Host '[5/5] Abrir Explorer...' -ForegroundColor Yellow
Start-Process explorer.exe $FtpPack

Write-Host ''
Write-Host 'PRONTO. Pasta para apagar no servidor e colar tudo:' -ForegroundColor Green
Write-Host $FtpPack -ForegroundColor Yellow
Write-Host '(copia tambem em deploy\fleaber_pt)' -ForegroundColor DarkGray
