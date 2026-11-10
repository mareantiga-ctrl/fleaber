# Gera pasta pronta para upload em fleaber.pt (nginx/cPanel — SEM suporte hosting)
# Uso: powershell -ExecutionPolicy Bypass -File tool/build_fleaber_pt_site.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$Website = Join-Path $RepoRoot "website"
$Out = Join-Path $RepoRoot "deploy\fleaber_pt"
$HubOut = Join-Path $Out "fleahub"
$FlutterBuild = Join-Path $RepoRoot "build\web"

Write-Host "=== Build fleaber.pt (site + Hub em /fleahub/) ===" -ForegroundColor Cyan
Write-Host "Repo: $RepoRoot"

Set-Location $RepoRoot

Write-Host ""
Write-Host "[1/4] flutter build web (hash URLs, base-href /fleahub/)..." -ForegroundColor Yellow
flutter build web --release `
    --base-href=/fleahub/ `
    --dart-define=FLEABER_WEB_HASH_URL=true `
    --dart-define=FLEABER_PUBLIC_REGISTRATION=false `
    --dart-define=FLEABER_HUB_DEV=true
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: flutter build web falhou." -ForegroundColor Red
    exit 1
}

Write-Host "[2/4] Limpar deploy\fleaber_pt..." -ForegroundColor Yellow
if (Test-Path $Out) {
    Remove-Item $Out -Recurse -Force
}
New-Item -ItemType Directory -Path $HubOut -Force | Out-Null

Write-Host "[3/4] Copiar Flutter para deploy/fleaber_pt/fleahub/..." -ForegroundColor Yellow
Copy-Item -Path (Join-Path $FlutterBuild "*") -Destination $HubOut -Recurse -Force

# Compat nginx/Apache antigos que pediam flutter_app.html na raiz
$HubIndex = Join-Path $HubOut "index.html"
$CompatRoot = Join-Path $Out "flutter_app.html"
if (Test-Path $HubIndex) {
    Copy-Item -Path $HubIndex -Destination $CompatRoot -Force
}

Write-Host "[4/4] Copiar website estatico (raiz)..." -ForegroundColor Yellow
Copy-Item -Path (Join-Path $Website "*") -Destination $Out -Recurse -Force
# Reaplicar compat depois do copy do website (não apagar)
if (Test-Path $HubIndex) {
    Copy-Item -Path $HubIndex -Destination $CompatRoot -Force
}

$Readme = Join-Path $Out "LEIA-ME-DEPLOY.txt"
@"
FLEABER.PT - PACOTE DE DEPLOY (nginx OK - sem suporte)
======================================================

Gera em: $(Get-Date -Format "yyyy-MM-dd HH:mm")

ESTRUTURA (upload TUDO para a raiz do dominio):

  index.html              Landing marketing
  hub.html                FleaHub com menu fleaber.pt
  fleahub.html            Atalho -> fleahub/index.html
  privacy.html, terms.html, refunds.html
  css/  js/  assets/

  fleahub/                APP FLUTTER (OBRIGATORIO - pasta inteira)
    index.html
    main.dart.js          (ficheiro grande - confirma no FTP!)
    flutter.js, canvaskit/, assets/, ...

COMO PUBLICAR:

  1. Backup do alojamento
  2. Apaga tudo na pasta publica
  3. Envia TODOS os ficheiros desta pasta (inclui pasta fleahub/)
  4. NAO precisas de nginx.conf nem suporte - rotas usam hash (#)

TESTES (depois do upload):

  https://fleaber.pt/                          -> landing
  https://fleaber.pt/hub.html                  -> FleaHub embed
  https://fleaber.pt/fleahub/                  -> Hub Flutter
  https://fleaber.pt/fleahub/index.html#/fleahub
  https://fleaber.pt/fleahub/index.html#/TEU_HANDLE/live

Registo publico: DESACTIVADO (fase testes).

FACEBOOK LOGIN (OBRIGATORIO no Supabase Dashboard):

  Authentication -> URL Configuration -> Redirect URLs, adicionar:
    https://fleaber.pt/fleahub/index.html

  (Site URL pode ser https://fleaber.pt/fleahub/index.html)

  Sem isto o login Facebook fica preso no spinner do Meta.
"@ | Set-Content -Path $Readme -Encoding UTF8

Write-Host ""
Write-Host "PRONTO - nginx nao precisa de config extra." -ForegroundColor Green
Write-Host "Pasta para upload FTP:" -ForegroundColor Yellow
Write-Host $Out
Write-Host ""
Write-Host "Confirma: fleahub\main.dart.js existe" -ForegroundColor Cyan
if (Test-Path (Join-Path $HubOut "main.dart.js")) {
    Write-Host "  OK main.dart.js" -ForegroundColor Green
} else {
    Write-Host "  ERRO: main.dart.js em falta!" -ForegroundColor Red
}
Start-Process explorer.exe $Out
