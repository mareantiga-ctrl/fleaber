# Fleaber PS - extensao Chrome (Facebook Live)

$ErrorActionPreference = "Stop"
$ext = $PSScriptRoot
$manifest = Join-Path $ext "manifest.json"

if (-not (Test-Path $manifest)) {
    Write-Host "ERRO: manifest.json nao encontrado em $ext" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Fleaber PS - Extensao Chrome ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Pasta da extensao (copiar para Chrome):" -ForegroundColor Yellow
Write-Host $ext
Write-Host ""
Write-Host "Passos:"
Write-Host "  1. Chrome -> chrome://extensions"
Write-Host "  2. Modo de programador ON"
Write-Host "  3. Carregar sem compactacao -> pasta acima"
Write-Host "  4. Clica no icone da extensao (quebra-cabeca, canto superior direito do Chrome)"
Write-Host "     -> Fleaber PS - Facebook Live -> abre o POPUP com campo do codigo"
Write-Host "     (Se nao vires: clique direito no icone -> Fixar / Pin)"
Write-Host "  5. Facebook Live no Chrome -> Activar leitura"
Write-Host ""

try {
    Start-Process "chrome://extensions/"
} catch {
    Write-Host "Abre manualmente: chrome://extensions/" -ForegroundColor DarkYellow
}

Write-Host "Chrome aberto. Usa a pasta indicada em amarelo." -ForegroundColor Green
