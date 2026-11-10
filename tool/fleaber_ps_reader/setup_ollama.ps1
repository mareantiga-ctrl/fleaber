# Fleaber PS - instalar Ollama (IA local) + activar no Reader
# Duplo-clique neste ficheiro (ou: powershell -File setup_ollama.ps1)

$ErrorActionPreference = "Stop"
Write-Host ""
Write-Host "=== Fleaber PS - Setup Ollama (IA local) ===" -ForegroundColor Cyan
Write-Host ""

function Find-OllamaExe {
    $paths = @(
        "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
        "$env:ProgramFiles\Ollama\ollama.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    $found = Get-Command ollama -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    return $null
}

$ollamaExe = Find-OllamaExe

if (-not $ollamaExe) {
    Write-Host "1/4 - Ollama ainda nao esta instalado." -ForegroundColor Yellow
    Write-Host "      Vou abrir o instalador. Clica:" -ForegroundColor White
    Write-Host "        Seguinte -> Seguinte -> Instalar -> Concluir" -ForegroundColor White
    Write-Host ""

    $installer = Join-Path $env:TEMP "OllamaSetup.exe"
    if (-not (Test-Path $installer)) {
        Write-Host "      A transferir instalador (~80 MB)..." -ForegroundColor Gray
        Invoke-WebRequest -Uri "https://ollama.com/download/OllamaSetup.exe" -OutFile $installer -UseBasicParsing
    }

    Start-Process -FilePath $installer -Wait
    Start-Sleep -Seconds 3
    $ollamaExe = Find-OllamaExe

    if (-not $ollamaExe) {
        Write-Host ""
        Write-Host "ERRO: Ollama nao encontrado apos instalacao." -ForegroundColor Red
        Write-Host "Reinicia o PC e corre este script outra vez." -ForegroundColor Yellow
        Read-Host "Enter para fechar"
        exit 1
    }
}

Write-Host "2/4 - Ollama encontrado: $ollamaExe" -ForegroundColor Green

Write-Host "3/4 - A transferir modelo IA (llama3.2:3b, ~2 GB)..." -ForegroundColor Yellow
& $ollamaExe pull llama3.2:3b
if ($LASTEXITCODE -ne 0) {
    Write-Host "AVISO: pull falhou. Tenta manualmente: ollama pull llama3.2:3b" -ForegroundColor Red
}

Write-Host "4/4 - A activar IA no Fleaber PS Reader..." -ForegroundColor Yellow
$configDir = Join-Path $env:APPDATA "FleaberReader"
$configPath = Join-Path $configDir "config.json"
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

if (Test-Path $configPath) {
    $raw = Get-Content $configPath -Raw -Encoding UTF8
    $config = $raw | ConvertFrom-Json
} else {
    $config = [PSCustomObject]@{}
}

$config | Add-Member -NotePropertyName ollama_enabled -NotePropertyValue $true -Force
$config | Add-Member -NotePropertyName ollama_url -NotePropertyValue "http://127.0.0.1:11434" -Force
$config | Add-Member -NotePropertyName ollama_model -NotePropertyValue "llama3.2:3b" -Force
($config | ConvertTo-Json -Depth 6) | Set-Content -Path $configPath -Encoding UTF8

Write-Host ""
Write-Host "PRONTO!" -ForegroundColor Green
Write-Host "  - Ollama instalado e modelo transferido" -ForegroundColor White
Write-Host "  - config.json: ollama_enabled = true" -ForegroundColor White
Write-Host ""
Write-Host "Agora: FECHA e REABRE o Fleaber PS Reader." -ForegroundColor Cyan
Write-Host "Marca a caixa IA local (Ollama) se ainda nao estiver activa." -ForegroundColor Cyan
Write-Host ""
Read-Host "Enter para fechar"
