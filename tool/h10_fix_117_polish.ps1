# H10 117 — artigo comercial, limpeza textos, imagem chat_image, conjunto real
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Get-Content (Join-Path $root 'tool\live_ops_production.env') | ForEach-Object {
  if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2].Trim() }
}

$Url = $env:SUPABASE_URL
$Key = $env:SUPABASE_SERVICE_ROLE_KEY
$Tag = 'H10_TESTE_COMPLETO_20261026'
$ChatId = '84cd817c-9068-4d0b-960a-8d41110da40b'
$MarianaId = '08c9dca8-3707-4ee5-9f43-b33293085d6a'
$ShopId = '06ed6f36-acfb-4c36-a3cf-d77a0eeeb451'
$MainProductId = 'b9aec2ff-56e3-4acd-9ff4-d6205ed1f40f'

$h = @{
  apikey        = $Key
  Authorization = "Bearer $Key"
  'Content-Type'= 'application/json'
  Prefer        = 'return=representation'
}

function Invoke-Sb($Method, $Path, $Body = $null, $Extra = @{}) {
  $headers = $h.Clone()
  foreach ($k in $Extra.Keys) { $headers[$k] = $Extra[$k] }
  $uri = "$Url$Path"
  if ($null -eq $Body) {
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers
  }
  $json = if ($Body -is [string]) { $Body } else { ($Body | ConvertTo-Json -Depth 20 -Compress) }
  return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($json))
}

function New-Fj([hashtable]$m) {
  return 'FLEABER_JSON_V1:' + ($m | ConvertTo-Json -Depth 12 -Compress)
}

Write-Host "=== H10 117 polish chat=$ChatId ==="

# --- 1) Artigo principal comercial com foto ---
$imgMain = "https://images.unsplash.com/photo-1551028719-00167b16eac5?auto=format&fit=crop&w=800&q=80"
Invoke-Sb PATCH "/rest/v1/products?id=eq.$MainProductId" @{
  title       = "Casaco de ganga Levis azul - tamanho M"
  price       = 42.0
  description = "Casaco de ganga Levis em azul classico, tamanho M. Usado com cuidado, sem rasgoes. Ideal para meia-estacao. Entrega combinada na conversa."
  state       = "Muito bom"
  image_urls  = @($imgMain)
  quantity    = 1
  is_sold     = $false
  list_on_marketplace = $true
} @{ Prefer = 'return=minimal' } | Out-Null
Write-Host "main_product_updated=$MainProductId"

# --- 2) Artigos para conjunto (BundleProposalChatCard) ---
$p2 = Invoke-Sb POST '/rest/v1/products' @{
  seller_id           = $ShopId
  title               = "Camisola knit bege - tamanho S"
  price               = 18.5
  ref_code            = 'H10BND2'
  description         = "Camisola de malha bege, leve, tamanho S. Seed $Tag"
  state               = "Bom"
  image_urls          = @("https://images.unsplash.com/photo-1434389677669-e08b4cac3105?auto=format&fit=crop&w=800&q=80")
  list_on_marketplace = $true
  available_for_live  = $false
  is_sold             = $false
  quantity            = 1
}
$P2Id = $p2[0].id

$p3 = Invoke-Sb POST '/rest/v1/products' @{
  seller_id           = $ShopId
  title               = "Cachecol de lã cinzento"
  price               = 12.0
  ref_code            = 'H10BND3'
  description         = "Cachecol de lã cinzento, macio. Seed $Tag"
  state               = "Bom"
  image_urls          = @("https://images.unsplash.com/photo-1601924994987-69e26d50dc26?auto=format&fit=crop&w=800&q=80")
  list_on_marketplace = $true
  available_for_live  = $false
  is_sold             = $false
  quantity            = 1
}
$P3Id = $p3[0].id
Write-Host "bundle_products=$P2Id,$P3Id"

$subtotal = 42.0 + 18.5 + 12.0
$discount = 7.25
$total = [math]::Round($subtotal - $discount, 2)
$bundle = Invoke-Sb POST '/rest/v1/product_bundles' @{
  seller_id    = $ShopId
  buyer_id     = $MarianaId
  chat_id      = $ChatId
  product_ids  = @($MainProductId, $P2Id, $P3Id)
  subtotal_eur = $subtotal
  discount_pct = [math]::Round(($discount / $subtotal) * 100, 1)
  discount_eur = $discount
  total_eur    = $total
  status       = 'pending'
}
$BundleId = $bundle[0].id
Write-Host "bundle_id=$BundleId"

# Remover nota técnica de conjunto (se existir)
$techMsgs = Invoke-Sb GET "/rest/v1/chat_messages?chat_id=eq.$ChatId&text=like.*Conjunto:%20demonstracao*&select=id"
foreach ($m in @($techMsgs)) {
  if ($m.id) {
    Invoke-Sb DELETE "/rest/v1/chat_messages?id=eq.$($m.id)" $null @{ Prefer = 'return=minimal' } | Out-Null
  }
}

$bundlePayload = @{
  kind            = 'bundle_proposal'
  bundle_id       = $BundleId
  product_ids     = @($MainProductId, $P2Id, $P3Id)
  product_quantities = @{ $MainProductId = 1; $P2Id = 1; $P3Id = 1 }
  seller_id       = $ShopId
  buyer_id        = $MarianaId
  subtotal_eur    = $subtotal
  discount_pct    = [math]::Round(($discount / $subtotal) * 100, 1)
  discount_eur    = $discount
  total_eur       = $total
  request_mode    = 'price_proposal'
  v               = 1
  proposal_ts     = (Get-Date).ToUniversalTime().ToString('o')
}
$bundleMsg = Invoke-Sb POST '/rest/v1/chat_messages' @{
  sender_id      = $MarianaId
  receiver_id    = $ShopId
  chat_id        = $ChatId
  text           = (New-Fj $bundlePayload)
  is_read        = $false
  is_reservation = $false
  created_at     = (Get-Date).ToUniversalTime().AddMinutes(-3).ToString('o')
}
Write-Host "bundle_msg=$($bundleMsg[0].id)"

# --- 3) Imagem real via chat_image (path em fleaber_private, sem URL externa) ---
$urlMsgs = Invoke-Sb GET "/rest/v1/chat_messages?chat_id=eq.$ChatId&text=like.https://picsum.photos*&select=id,text"
foreach ($m in @($urlMsgs)) {
  if ($m.id) {
    Invoke-Sb DELETE "/rest/v1/chat_messages?id=eq.$($m.id)" $null @{ Prefer = 'return=minimal' } | Out-Null
  }
}

# Download imagem e upload storage
$tmpJpg = Join-Path $env:TEMP "h10_117_chat_img.jpg"
Invoke-WebRequest -Uri "https://images.unsplash.com/photo-1523381216712-77745c48ceeb?auto=format&fit=crop&w=640&q=70" -OutFile $tmpJpg -UseBasicParsing
$bytes = [System.IO.File]::ReadAllBytes($tmpJpg)
$storagePath = "chat_uploads/$MarianaId/$ChatId/h10_117_$(Get-Date -Format 'yyyyMMddHHmmss').jpg"
$uploadUri = "$Url/storage/v1/object/fleaber_private/$storagePath"
$upHeaders = @{
  apikey        = $Key
  Authorization = "Bearer $Key"
  'Content-Type'= 'image/jpeg'
  'x-upsert'    = 'true'
}
try {
  Invoke-RestMethod -Method POST -Uri $uploadUri -Headers $upHeaders -Body $bytes | Out-Null
  Write-Host "uploaded=$storagePath"
  $imgPayload = New-Fj @{ kind = 'chat_image'; path = $storagePath; url = ''; v = 2 }
  $imgMsg = Invoke-Sb POST '/rest/v1/chat_messages' @{
    sender_id      = $MarianaId
    receiver_id    = $ShopId
    chat_id        = $ChatId
    text           = $imgPayload
    is_read        = $false
    is_reservation = $false
    created_at     = (Get-Date).ToUniversalTime().AddMinutes(-2).ToString('o')
  }
  Write-Host "chat_image_msg=$($imgMsg[0].id)"
} catch {
  Write-Host "WARN chat_image upload failed: $($_.Exception.Message)"
  # Fallback: path-only may still fail without file — leave note in inventory
}

# --- 4) Limpar / humanizar textos técnicos ---
$longPt = [string]([char]0x4F)+[char]0x6C+[char]0xE1+"! Queria confirmar que o balao acomoda varias linhas sem partir o layout. Preciso de ver o preco, o envio, a proteccao Fleaber e o prazo de reserva no mesmo ecra, com scroll confortavel ate ao fim da conversa."
# UTF-8 natural PT via .NET
$longPt = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes("Ola! Queria confirmar que o balao acomoda varias linhas sem partir o layout. Preciso de ver o preco, o envio, a proteccao Fleaber e o prazo de reserva no mesmo ecra, com scroll confortavel ate ao fim da conversa."))
$utf8 = New-Object System.Text.UTF8Encoding $false
$longPt = $utf8.GetString([byte[]](0x4F,0x6C,0xC3,0xA1,0x21)) + " Queria confirmar que o balão acomoda várias linhas sem partir o layout. Preciso de ver o preço, o envio, a protecção Fleaber e o prazo de reserva no mesmo ecrã, com scroll confortável até ao fim da conversa."
# Safer: write via file to avoid console codepage issues
$longFile = Join-Path $env:TEMP 'h10_117_long.txt'
[System.IO.File]::WriteAllText($longFile, "Olá! Queria confirmar que o balão acomoda várias linhas sem partir o layout. Preciso de ver o preço, o envio, a protecção Fleaber e o prazo de reserva no mesmo ecrã, com scroll confortável até ao fim da conversa.", [System.Text.UTF8Encoding]::new($false))
$longPt = [System.IO.File]::ReadAllText($longFile, [System.Text.UTF8Encoding]::new($false))
$longHits = Invoke-Sb GET "/rest/v1/chat_messages?chat_id=eq.$ChatId&text=like.Texto%20longo%20de%20teste*&select=id"
foreach ($m in @($longHits)) {
  if ($m.id) {
    Invoke-Sb PATCH "/rest/v1/chat_messages?id=eq.$($m.id)" @{ text = $longPt } @{ Prefer = 'return=minimal' } | Out-Null
  }
}

$finalFile = Join-Path $env:TEMP 'h10_117_final.txt'
[System.IO.File]::WriteAllText($finalFile, "Mensagem do vendedor: o historico desta conversa esta pronto para revisao visual.", [System.Text.UTF8Encoding]::new($false))
$finalPt = [System.IO.File]::ReadAllText($finalFile, [System.Text.UTF8Encoding]::new($false))
$finalHits = Invoke-Sb GET "/rest/v1/chat_messages?chat_id=eq.$ChatId&text=like.Mensagem%20final%20do%20vendedor*&select=id"
foreach ($m in @($finalHits)) {
  if ($m.id) {
    Invoke-Sb PATCH "/rest/v1/chat_messages?id=eq.$($m.id)" @{ text = $finalPt } @{ Prefer = 'return=minimal' } | Out-Null
  }
}

$olaFile = Join-Path $env:TEMP 'h10_117_ola.txt'
[System.IO.File]::WriteAllText($olaFile, "Ola! Tenho interesse neste casaco de ganga. Ainda esta disponivel?", [System.Text.UTF8Encoding]::new($false))
$olaText = [System.IO.File]::ReadAllText($olaFile, [System.Text.UTF8Encoding]::new($false))
$olaHits = Invoke-Sb GET "/rest/v1/chat_messages?chat_id=eq.$ChatId&text=like.Ola!%20Queria%20ver*&select=id"
foreach ($m in @($olaHits)) {
  if ($m.id) {
    Invoke-Sb PATCH "/rest/v1/chat_messages?id=eq.$($m.id)" @{ text = $olaText } @{ Prefer = 'return=minimal' } | Out-Null
  }
}

$ola2File = Join-Path $env:TEMP 'h10_117_ola2.txt'
[System.IO.File]::WriteAllText($ola2File, "Ola! Sim, podes reservar ou fazer uma proposta - responde aqui na conversa.", [System.Text.UTF8Encoding]::new($false))
$ola2Text = [System.IO.File]::ReadAllText($ola2File, [System.Text.UTF8Encoding]::new($false))
$ola2 = Invoke-Sb GET "/rest/v1/chat_messages?chat_id=eq.$ChatId&text=like.Ola!%20Podes%20reservar*&select=id"
foreach ($m in @($ola2)) {
  if ($m.id) {
    Invoke-Sb PATCH "/rest/v1/chat_messages?id=eq.$($m.id)" @{ text = $ola2Text } @{ Prefer = 'return=minimal' } | Out-Null
  }
}

# Aviso Fleaber com nome comercial (mensagem 75)
$sysHits = Invoke-Sb GET "/rest/v1/chat_messages?chat_id=eq.$ChatId&text=like.*fleaber_res*&select=id,text"
foreach ($m in @($sysHits)) {
  if (-not $m.id) { continue }
  $clean = $m.text -replace '\[H10_TESTE[^\]]*\]\s*', ''
  $clean = $clean -replace 'Artigo A - camisola azul', 'Casaco de ganga Levis azul - tamanho M'
  if ($clean -ne $m.text) {
    Invoke-Sb PATCH "/rest/v1/chat_messages?id=eq.$($m.id)" @{ text = $clean } @{ Prefer = 'return=minimal' } | Out-Null
  }
}

# Expirados — títulos limpos
$exp1 = Invoke-Sb GET "/rest/v1/chat_messages?chat_id=eq.$ChatId&text=like.*pending_expired*&select=id"
foreach ($m in @($exp1)) {
  if ($m.id) {
    Invoke-Sb PATCH "/rest/v1/chat_messages?id=eq.$($m.id)" @{
      text = (New-Fj @{ kind = 'pending_expired_buyer_notice'; title = 'O prazo do pedido de reserva expirou.' })
    } @{ Prefer = 'return=minimal' } | Out-Null
  }
}
$exp2 = Invoke-Sb GET "/rest/v1/chat_messages?chat_id=eq.$ChatId&text=like.*guaranteed_expired*&select=id"
foreach ($m in @($exp2)) {
  if ($m.id) {
    Invoke-Sb PATCH "/rest/v1/chat_messages?id=eq.$($m.id)" @{
      text = (New-Fj @{ kind = 'guaranteed_expired_buyer_notice'; title = 'A reserva garantida expirou.' })
    } @{ Prefer = 'return=minimal' } | Out-Null
  }
}

# last_message legível
Invoke-Sb PATCH "/rest/v1/chats?id=eq.$ChatId" @{
  last_message      = 'Proposta de conjunto · 3 artigos'
  last_message_time = (Get-Date).ToUniversalTime().ToString('o')
  product_id        = $MainProductId
} @{ Prefer = 'return=minimal' } | Out-Null

$msgs = Invoke-Sb GET "/rest/v1/chat_messages?chat_id=eq.$ChatId&select=id&order=created_at.asc"
$out = [ordered]@{
  chat_id           = $ChatId
  main_product_id   = $MainProductId
  bundle_id         = $BundleId
  bundle_product_ids= @($MainProductId, $P2Id, $P3Id)
  message_count     = @($msgs).Count
  tag               = $Tag
  account           = 'mareantiga@gmail.com'
}
$rep = Join-Path $root 'tool\reports\fleahub_h10_mensagens_117_2026-10-26'
New-Item -ItemType Directory -Force -Path $rep | Out-Null
$out | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $rep 'INVENTARIO_DADOS_TESTE.json') -Encoding UTF8
Write-Host ($out | ConvertTo-Json -Compress)
Write-Host "=== DONE 117 polish ==="
