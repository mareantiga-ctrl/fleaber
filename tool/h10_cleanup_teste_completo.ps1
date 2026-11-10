# Limpeza seed H10 TESTE COMPLETO (antes do lancamento publico).
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Get-Content (Join-Path $root 'tool\live_ops_production.env') | ForEach-Object {
  if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2].Trim() }
}
$Tag = 'H10_TESTE_COMPLETO_20261026'
$BuyerEmail = 'h10.teste.completo@fleaber.test'
$invPath = Join-Path $root 'tool\reports\fleahub_h10_mensagens_116_2026-10-26\INVENTARIO_DADOS_TESTE.json'
$inv = Get-Content $invPath | ConvertFrom-Json
$h = @{
  apikey        = $env:SUPABASE_SERVICE_ROLE_KEY
  Authorization = "Bearer $($env:SUPABASE_SERVICE_ROLE_KEY)"
  Prefer        = 'return=minimal'
}
$BuyerId = $inv.buyer_id
$ChatId = $inv.chat_id
Write-Host "cleanup tag=$Tag chat=$ChatId buyer=$BuyerId"
Invoke-RestMethod -Method DELETE -Uri "$($env:SUPABASE_URL)/rest/v1/chat_messages?chat_id=eq.$ChatId" -Headers $h | Out-Null
Invoke-RestMethod -Method DELETE -Uri "$($env:SUPABASE_URL)/rest/v1/chats?id=eq.$ChatId" -Headers $h | Out-Null
Invoke-RestMethod -Method DELETE -Uri "$($env:SUPABASE_URL)/rest/v1/orders?buyer_id=eq.$BuyerId" -Headers $h | Out-Null
Invoke-RestMethod -Method DELETE -Uri "$($env:SUPABASE_URL)/rest/v1/products?title=like.*$Tag*" -Headers $h | Out-Null
Write-Host "REST limpo. Remover auth user $BuyerEmail no dashboard Auth se necessario."
Write-Host "DONE"
