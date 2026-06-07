# Instala Maestro CLI no Windows (PowerShell).
# Uso: powershell -ExecutionPolicy Bypass -File tool/install_maestro.ps1
$ErrorActionPreference = "Stop"
Write-Host "A instalar Maestro CLI..."
try {
  irm https://get.maestro.mobile.dev | iex
  maestro --version
  Write-Host "OK. Corre: maestro test .maestro/flows/"
} catch {
  Write-Host "Falha. Instala manualmente: https://maestro.mobile.dev/getting-started/installing-maestro"
  exit 1
}
