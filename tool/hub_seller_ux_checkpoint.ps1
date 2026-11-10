# DEPRECATED — usar hub_seller_ux_validate.ps1 (automatico; pausa so em erro).
# Uso: powershell -File tool/hub_seller_ux_validate.ps1
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "hub_seller_ux_validate.ps1") @args
