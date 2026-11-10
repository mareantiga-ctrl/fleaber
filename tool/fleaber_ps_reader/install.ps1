# Fleaber PS Reader - Instalacao Windows
# Executar: powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $Root "..\..")
$Venv = Join-Path $RepoRoot ".venv"
$AppDir = $Root

Write-Host "=== Fleaber PS Reader - Instalacao ===" -ForegroundColor Cyan

if (-not (Test-Path $Venv)) {
    Write-Host "A criar ambiente virtual..."
    py -3.11 -m venv $Venv 2>$null
    if (-not (Test-Path $Venv)) {
        python -m venv $Venv
    }
}

& (Join-Path $Venv "Scripts\Activate.ps1")
pip install -q -r (Join-Path $AppDir "requirements.txt")

$tess = Get-Command tesseract -ErrorAction SilentlyContinue
if (-not $tess) {
    Write-Host ""
    Write-Host "AVISO: Tesseract OCR nao encontrado no PATH." -ForegroundColor Yellow
    Write-Host "Instala: winget install UB-Mannheim.TesseractOCR" -ForegroundColor Yellow
}

$Desktop = [Environment]::GetFolderPath("Desktop")
$Shortcut = Join-Path $Desktop "Fleaber PS Reader.lnk"
$Wsh = New-Object -ComObject WScript.Shell
$Sc = $Wsh.CreateShortcut($Shortcut)
$Sc.TargetPath = Join-Path $Venv "Scripts\pythonw.exe"
$Sc.Arguments = "-m fleaber_ps"
$Sc.WorkingDirectory = $AppDir
$Sc.Description = "Fleaber PS Reader - Facebook OCR"
$Sc.Save()

Write-Host ""
Write-Host "OK Instalado. Atalho:" $Shortcut -ForegroundColor Green
Write-Host "Abre 'Fleaber PS Reader' no ambiente de trabalho." -ForegroundColor Green
Write-Host ""
Write-Host "EXE opcional: pip install pyinstaller; pyinstaller build.spec"
