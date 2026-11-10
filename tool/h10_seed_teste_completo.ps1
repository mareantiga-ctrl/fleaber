# Seed H10 - conversa persistente «TESTE COMPLETO - H10» (producao, marcada limpeza).
# Nao executa pagamentos bancarios nem envios físicos.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Get-Content (Join-Path $root 'tool\live_ops_production.env') | ForEach-Object {
  if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2].Trim() }
}

$SellerId = $env:PROD_TEST_SELLER_ID
$Url = $env:SUPABASE_URL
$Key = $env:SUPABASE_SERVICE_ROLE_KEY
$BuyerEmail = 'h10.teste.completo@fleaber.test'
$BuyerPass = 'H10-TesteCompleto!aA1'
$Tag = 'H10_TESTE_COMPLETO_20261026'
$BuyerName = 'TESTE COMPLETO - H10'

$h = @{
  apikey         = $Key
  Authorization  = "Bearer $Key"
  'Content-Type' = 'application/json'
  Prefer         = 'return=representation'
}

function Invoke-Sb {
  param([string]$Method, [string]$Path, [object]$Body = $null, [hashtable]$ExtraHeaders = @{})
  $headers = $h.Clone()
  foreach ($k in $ExtraHeaders.Keys) { $headers[$k] = $ExtraHeaders[$k] }
  $uri = "$Url$Path"
  if ($null -eq $Body) {
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers
  }
  $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }
  return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($json))
}

function New-FleaberJson([hashtable]$map) {
  return 'FLEABER_JSON_V1:' + ($map | ConvertTo-Json -Depth 10 -Compress)
}

Write-Host "=== H10 seed $Tag ==="

# 1) Buyer auth user (idempotent lookup)
$existing = $null
try {
  $users = Invoke-Sb GET "/auth/v1/admin/users?page=1&per_page=200" -ExtraHeaders @{ Accept = 'application/json' }
  $existing = @($users.users) | Where-Object { $_.email -eq $BuyerEmail } | Select-Object -First 1
} catch {
  Write-Host "admin users list fail: $($_.Exception.Message)"
}

if ($existing) {
  $BuyerId = $existing.id
  Write-Host "buyer exists $BuyerId"
} else {
  $created = Invoke-Sb POST "/auth/v1/admin/users" @{
    email          = $BuyerEmail
    password       = $BuyerPass
    email_confirm  = $true
    user_metadata  = @{ full_name = $BuyerName; h10_seed = $Tag }
  }
  $BuyerId = $created.id
  Write-Host "buyer created $BuyerId"
}

# 2) Profile upsert
Invoke-Sb POST "/rest/v1/profiles?on_conflict=id" @{
  id         = $BuyerId
  full_name  = $BuyerName
  user_type  = 'comprador'
  location   = 'Lisboa'
  handle     = 'h10-teste-completo'
} -ExtraHeaders @{ Prefer = 'resolution=merge-duplicates,return=representation' } | Out-Null

# 3) Products (seller) - marked in title
$products = @()
foreach ($spec in @(
    @{ title = "[$Tag] Artigo A - camisola azul"; price = 12.5; ref = 'H10A' },
    @{ title = "[$Tag] Artigo B - calcas vintage"; price = 18.0; ref = 'H10B' },
    @{ title = "[$Tag] Artigo C - conjunto demo"; price = 28.5; ref = 'H10C' }
  )) {
  $row = Invoke-Sb POST "/rest/v1/products" @{
    seller_id              = $SellerId
    title                  = $spec.title
    price                  = $spec.price
    ref_code               = $spec.ref
    description            = "Seed $Tag - limpar antes do lancamento."
    state                  = 'Bom'
    image_urls             = @()
    list_on_marketplace    = $true
    available_for_live     = $false
    is_sold                = $false
    quantity               = 3
  }
  $products += $row[0]
  Write-Host "product $($row[0].id) $($spec.ref)"
}

$MainProduct = $products[0]

# 4) Chat
$chat = Invoke-Sb POST "/rest/v1/chats" @{
  user_a             = $BuyerId
  user_b             = $SellerId
  product_id         = $MainProduct.id
  last_message       = 'TESTE COMPLETO - H10 | historico de demonstracao'
  last_message_time  = (Get-Date).ToUniversalTime().ToString('o')
}
$ChatId = $chat[0].id
Write-Host "chat $ChatId"

# 5) Minimal orders for payloads that need order_id (no real payment)
# Statusos reais BD (orders_status_batata_check): pendente|pago|enviado|entregue|cancelado
$orderDefs = @(
  @{ status = 'pendente'; note = 'reserva_pendente' },
  @{ status = 'pendente'; note = 'reserva_aceite' },
  @{ status = 'cancelado'; note = 'reserva_recusada' },
  @{ status = 'cancelado'; note = 'reserva_cancelada' },
  @{ status = 'pago'; note = 'pago' },
  @{ status = 'enviado'; note = 'enviado' },
  @{ status = 'entregue'; note = 'concluido' },
  @{ status = 'pago'; note = 'disputa' }
)
$orders = @()
$i = 0
foreach ($od in $orderDefs) {
  $prodId = $products[$i % $products.Count].id
  $i++
  $body = @{
    buyer_id       = $BuyerId
    seller_id      = $SellerId
    product_id     = $prodId
    quantity       = 1
    status         = $od.status
    is_reservation = $true
    price_total    = 12.5
  }
  try {
    $o = Invoke-Sb POST "/rest/v1/orders" $body
    $orders += [pscustomobject]@{ row = $o[0]; note = $od.note }
    Write-Host "order $($o[0].id) $($od.note)"
  } catch {
    Write-Host "order skip $($od.note): $($_.Exception.Message)"
  }
}

function Find-Order([string]$note) {
  return ($orders | Where-Object { $_.note -eq $note } | Select-Object -First 1).row
}

$t0 = [DateTime]::UtcNow.AddHours(-6)
function Stamp([int]$mins) { return $t0.AddMinutes($mins).ToString('o') }

$msgs = [System.Collections.Generic.List[object]]::new()
function Add-Msg {
  param($from, $to, $text, $mins, [bool]$res = $false)
  $msgs.Add(@{
      chat_id         = $ChatId
      sender_id       = $from
      receiver_id     = $to
      text            = $text
      is_read         = $true
      is_reservation  = $res
      created_at      = (Stamp $mins)
    })
}

# Texto normal
Add-Msg $BuyerId $SellerId 'Ola! Queria ver as opcões deste artigo de teste H10.' 1
Add-Msg $SellerId $BuyerId 'Ola! Podes reservar ou fazer proposta - esta conversa e o TESTE COMPLETO H10.' 2

# Ofertas
Add-Msg $BuyerId $SellerId (New-FleaberJson @{
    kind   = 'price_offer'
    amount = 10.0
    note   = $Tag
  }) 5
Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind    = 'price_offer_outcome'
    outcome = 'rejected'
    amount  = 10.0
  }) 6
Add-Msg $BuyerId $SellerId (New-FleaberJson @{
    kind   = 'price_offer'
    amount = 11.5
    note   = $Tag
  }) 7
Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind    = 'price_offer_outcome'
    outcome = 'accepted'
    amount  = 11.5
  }) 8

# Reservas - varios estados
$op = Find-Order 'reserva_pendente'
Add-Msg $BuyerId $SellerId (New-FleaberJson @{
    kind     = 'reservation_request'
    order_id = $op.id
    qty      = 1
    title    = $MainProduct.title
  }) 10 $true

$oa = Find-Order 'reserva_aceite'
Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind     = 'reservation_request_outcome'
    outcome  = 'accepted'
    order_id = $oa.id
  }) 11 $true
Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind     = 'reservation_accepted'
    order_id = $oa.id
  }) 12 $true

$or = Find-Order 'reserva_recusada'
Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind     = 'reservation_request_outcome'
    outcome  = 'rejected'
    order_id = $or.id
  }) 13 $true

Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind = 'reservation_reminder'
  }) 14 $true
Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind = 'reservation_payment_check_reminder'
  }) 15 $true

$oc = Find-Order 'reserva_cancelada'
Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind     = 'reservation_cancelled_by_seller'
    order_id = $oc.id
  }) 16 $true

# Pagamento / envio / conclusao
$opaid = Find-Order 'pago'
Add-Msg $BuyerId $SellerId (New-FleaberJson @{
    kind     = 'reservation_payment_submitted'
    order_id = $opaid.id
    amount   = 14.9
  }) 20 $true
Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind     = 'seguro_fleaber_paid'
    order_id = $opaid.id
    total    = 14.9
  }) 21

$os = Find-Order 'enviado'
Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind     = 'reservation_order_shipped'
    order_id = $os.id
  }) 22 $true
Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind = 'reservation_shipping_reminder'
  }) 23 $true

$odone = Find-Order 'concluido'
Add-Msg $BuyerId $SellerId (New-FleaberJson @{
    kind     = 'reservation_seller_confirmed_receipt'
    order_id = $odone.id
  }) 24 $true
Add-Msg $BuyerId $SellerId (New-FleaberJson @{
    kind     = 'reservation_order_completed'
    order_id = $odone.id
  }) 25 $true
Add-Msg $BuyerId $SellerId (New-FleaberJson @{
    kind     = 'order_review_submitted'
    order_id = $odone.id
    rating   = 5
  }) 26
Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind = 'auto_feedback_generated'
  }) 27

# Cancelamento pedido
Add-Msg $BuyerId $SellerId (New-FleaberJson @{
    kind   = 'cancel_request'
    reason = 'Mudei de ideias (seed H10)'
  }) 30
Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind    = 'cancel_request_outcome'
    outcome = 'accepted'
  }) 31
Add-Msg $BuyerId $SellerId (New-FleaberJson @{
    kind   = 'cancel_request'
    reason = 'Segundo pedido (recusado - seed)'
  }) 32
Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind    = 'cancel_request_outcome'
    outcome = 'rejected'
  }) 33

# Disputa
$odisp = Find-Order 'disputa'
Add-Msg $BuyerId $SellerId (New-FleaberJson @{
    kind     = 'order_dispute_opened'
    order_id = $odisp.id
    reason   = 'danificado'
    note     = "Seed $Tag"
  }) 35

# Rifa
Add-Msg $SellerId $BuyerId (New-FleaberJson @{
    kind  = 'raffle_prize_awarded'
    title = "[$Tag] Premio rifa demo"
  }) 40

# Sistema legado (texto)
Add-Msg $SellerId $BuyerId @"
Fleaber | sistema
Reserva garantida
$($MainProduct.title) | 1 unidade
Reservado ate amanha (hora de Lisboa).
Paga no saco ate esta hora.

[[fleaber_res:reservation_guaranteed:seed-$Tag]]
"@ 41 $true

Add-Msg $BuyerId $SellerId 'Mensagem final do comprador - percorre o historico completo acima.' 50
Add-Msg $SellerId $BuyerId 'Mensagem final do vendedor - TESTE COMPLETO H10 pronto para revisao visual.' 51

# Insert messages
$inserted = 0
foreach ($m in $msgs) {
  try {
    Invoke-Sb POST "/rest/v1/chat_messages" $m | Out-Null
    $inserted++
  } catch {
    Write-Host "msg fail min=$($m.created_at): $($_.Exception.Message)"
  }
}

# Bump chat preview
Invoke-Sb PATCH "/rest/v1/chats?id=eq.$ChatId" @{
  last_message      = 'TESTE COMPLETO - H10 | historico de demonstracao'
  last_message_time = (Get-Date).ToUniversalTime().ToString('o')
} -ExtraHeaders @{ Prefer = 'return=minimal' } | Out-Null

$out = [ordered]@{
  tag            = $Tag
  chat_id        = $ChatId
  seller_id      = $SellerId
  seller_email   = $env:PROD_TEST_SELLER_EMAIL
  buyer_id       = $BuyerId
  buyer_email    = $BuyerEmail
  buyer_name     = $BuyerName
  product_ids    = @($products | ForEach-Object { $_.id })
  order_ids      = @($orders | ForEach-Object { $_.row.id })
  messages_count = $inserted
  cleanup_note   = "Apagar produtos title LIKE '[$Tag]%', orders/chat/messages ligados, auth user $BuyerEmail"
}
$outPath = Join-Path $root 'tool\reports\fleahub_h10_mensagens_116_2026-10-26\INVENTARIO_DADOS_TESTE.json'
New-Item -ItemType Directory -Force -Path (Split-Path $outPath) | Out-Null
$out | ConvertTo-Json -Depth 5 | Set-Content $outPath -Encoding UTF8
Write-Host "DONE messages=$inserted inventory=$outPath"
$out | ConvertTo-Json -Compress
