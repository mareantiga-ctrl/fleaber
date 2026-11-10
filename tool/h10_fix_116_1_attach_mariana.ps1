# 116.1 — Associar TESTE COMPLETO - H10 a mareantiga@gmail.com + artigo com Comprar/Proposta
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Get-Content (Join-Path $root 'tool\live_ops_production.env') | ForEach-Object {
  if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2].Trim() }
}

$Url = $env:SUPABASE_URL
$Key = $env:SUPABASE_SERVICE_ROLE_KEY
$Tag = 'H10_TESTE_COMPLETO_20261026'
$MarianaId = '08c9dca8-3707-4ee5-9f43-b33293085d6a' # mareantiga@gmail.com
$ShopId = '06ed6f36-acfb-4c36-a3cf-d77a0eeeb451'   # TESTE COMPLETO - H10
$OldSeller = $env:PROD_TEST_SELLER_ID
$ChatId = '84cd817c-9068-4d0b-960a-8d41110da40b'

$h = @{
  apikey         = $Key
  Authorization  = "Bearer $Key"
  'Content-Type' = 'application/json'
  Prefer         = 'return=representation'
}

function Invoke-Sb($Method, $Path, $Body = $null, $Extra = @{}) {
  $headers = $h.Clone()
  foreach ($k in $Extra.Keys) { $headers[$k] = $Extra[$k] }
  $uri = "$Url$Path"
  if ($null -eq $Body) { return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers }
  $json = if ($Body -is [string]) { $Body } else { ($Body | ConvertTo-Json -Depth 20 -Compress) }
  return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($json))
}

function New-Fj([hashtable]$m) { return 'FLEABER_JSON_V1:' + ($m | ConvertTo-Json -Depth 12 -Compress) }

Write-Host "=== 116.1 attach Mariana -> chat $ChatId ==="

# Shop profile must look like a seller for the conversation name
Invoke-Sb POST '/rest/v1/profiles?on_conflict=id' @{
  id         = $ShopId
  full_name  = 'TESTE COMPLETO - H10'
  user_type  = 'vendedor'
  location   = 'Lisboa'
  handle     = 'h10-teste-completo'
} @{ Prefer = 'resolution=merge-duplicates,return=minimal' } | Out-Null

# Available product (Buy + Offer) — no order on this product_id for this chat
$avail = Invoke-Sb POST '/rest/v1/products' @{
  seller_id           = $ShopId
  title               = "[$Tag] Artigo DISPONIVEL - com Comprar e Proposta"
  price               = 15.9
  ref_code            = 'H10AVAIL'
  description         = "Seed $Tag disponivel para compra/proposta"
  state               = 'Bom'
  image_urls          = @('https://bpmpkzwnrbmuqnhgdscf.supabase.co/storage/v1/object/public/product-images/placeholder-h10.png')
  list_on_marketplace = $true
  available_for_live  = $false
  is_sold             = $false
  quantity            = 5
}
$AvailId = $avail[0].id
Write-Host "available_product=$AvailId"

# Extra products for history states (keep old ones; add image-capable)
$histProd = Invoke-Sb POST '/rest/v1/products' @{
  seller_id           = $ShopId
  title               = "[$Tag] Artigo historico - estados"
  price               = 22.0
  ref_code            = 'H10HIST'
  description         = "Seed $Tag historico"
  state               = 'Bom'
  image_urls          = @()
  list_on_marketplace = $true
  available_for_live  = $false
  is_sold             = $false
  quantity            = 2
}
$HistId = $histProd[0].id

# Reassign chat to Mariana <-> TESTE COMPLETO, main product = available
Invoke-Sb PATCH "/rest/v1/chats?id=eq.$ChatId" @{
  user_a            = $MarianaId
  user_b            = $ShopId
  product_id        = $AvailId
  last_message      = 'TESTE COMPLETO - H10 | historico completo'
  last_message_time = (Get-Date).ToUniversalTime().ToString('o')
} @{ Prefer = 'return=minimal' } | Out-Null
Write-Host 'chat participants updated'

# Remap existing message senders: old buyer(ShopId)->Mariana, old seller(vendedora)->ShopId
$msgs = Invoke-Sb GET "/rest/v1/chat_messages?chat_id=eq.$ChatId&select=id,sender_id,receiver_id"
foreach ($m in $msgs) {
  $newSender = $m.sender_id
  $newRecv = $m.receiver_id
  if ($m.sender_id -eq $ShopId) { $newSender = $MarianaId }
  elseif ($m.sender_id -eq $OldSeller) { $newSender = $ShopId }
  if ($m.receiver_id -eq $ShopId) { $newRecv = $MarianaId }
  elseif ($m.receiver_id -eq $OldSeller) { $newRecv = $ShopId }
  if ($newSender -ne $m.sender_id -or $newRecv -ne $m.receiver_id) {
    Invoke-Sb PATCH "/rest/v1/chat_messages?id=eq.$($m.id)" @{
      sender_id   = $newSender
      receiver_id = $newRecv
    } @{ Prefer = 'return=minimal' } | Out-Null
  }
}
Write-Host 'messages remapped'

# Orders: move buyer to Mariana; keep product refs on hist products (not AvailId)
$orders = Invoke-Sb GET "/rest/v1/orders?buyer_id=eq.$ShopId&select=id,product_id,status"
foreach ($o in @($orders)) {
  Invoke-Sb PATCH "/rest/v1/orders?id=eq.$($o.id)" @{
    buyer_id   = $MarianaId
    seller_id  = $ShopId
    product_id = $HistId
  } @{ Prefer = 'return=minimal' } | Out-Null
}
Write-Host ("orders_moved=" + @($orders).Count)

# Append missing coverage: long text, image, expired offer, expired reservation notice, bundle-ish note
$t = [DateTime]::UtcNow
function Stamp([int]$s) { $t.AddSeconds($s).ToString('o') }

$extra = @(
  @{
    chat_id=$ChatId; sender_id=$MarianaId; receiver_id=$ShopId; is_read=$true; is_reservation=$false
    created_at=(Stamp 1)
    text='Texto longo de teste: quero confirmar que o balão acomoda várias linhas sem partir o layout. Preciso de ver o preço, o envio, a protecção Fleaber e o prazo de reserva no mesmo ecrã, com scroll confortável no histórico completo da conversa TESTE COMPLETO - H10.'
  },
  @{
    chat_id=$ChatId; sender_id=$MarianaId; receiver_id=$ShopId; is_read=$true; is_reservation=$false
    created_at=(Stamp 2)
    text=(New-Fj @{ kind='chat_image'; url='https://picsum.photos/seed/h10fleaber/640/480'; path='' })
  },
  @{
    chat_id=$ChatId; sender_id=$ShopId; receiver_id=$MarianaId; is_read=$true; is_reservation=$false
    created_at=(Stamp 3)
    text=(New-Fj @{ kind='price_offer_outcome'; outcome='expired'; amount=9.5 })
  },
  @{
    chat_id=$ChatId; sender_id=$ShopId; receiver_id=$MarianaId; is_read=$true; is_reservation=$true
    created_at=(Stamp 4)
    text=(New-Fj @{ kind='pending_expired_buyer_notice'; title='Reserva expirada (seed H10)' })
  },
  @{
    chat_id=$ChatId; sender_id=$ShopId; receiver_id=$MarianaId; is_read=$true; is_reservation=$true
    created_at=(Stamp 5)
    text=(New-Fj @{ kind='guaranteed_expired_buyer_notice'; title='Reserva garantida expirada (seed H10)' })
  },
  @{
    chat_id=$ChatId; sender_id=$MarianaId; receiver_id=$ShopId; is_read=$true; is_reservation=$false
    created_at=(Stamp 6)
    text=(New-Fj @{ kind='cancel_request_outcome'; outcome='refunded'; display='Reembolso registado (seed H10 — sem transferencia real).' })
  },
  @{
    chat_id=$ChatId; sender_id=$ShopId; receiver_id=$MarianaId; is_read=$true; is_reservation=$false
    created_at=(Stamp 7)
    text='Conjunto: demonstracao visual via cartao de artigo principal disponivel + historico de estados noutros artigos da mesma conversa (BundleProposalChatCard completo exige bundle_id com fetch — ver limitacoes).'
  }
)

$n = 0
foreach ($m in $extra) {
  try { Invoke-Sb POST '/rest/v1/chat_messages' $m | Out-Null; $n++ } catch { Write-Host "extra fail: $($_.Exception.Message)" }
}
Write-Host "extra_messages=$n"

$total = @(Invoke-Sb GET "/rest/v1/chat_messages?chat_id=eq.$ChatId&select=id").Count
$out = [ordered]@{
  tag                 = $Tag
  authenticated_account = 'mareantiga@gmail.com'
  authenticated_user_id = $MarianaId
  authenticated_name  = 'Mariana Soares'
  chat_id             = $ChatId
  other_party_name    = 'TESTE COMPLETO - H10'
  other_party_id      = $ShopId
  available_product_id = $AvailId
  history_product_id  = $HistId
  messages_total      = $total
  list_label          = 'TESTE COMPLETO - H10'
  buy_offer_expected  = $true
}
$rep = Join-Path $root 'tool\reports\fleahub_h10_mensagens_116_1_2026-10-26'
New-Item -ItemType Directory -Force -Path $rep | Out-Null
$out | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $rep 'IDENTIDADE_SESSAO_E_CONVERSA.json') -Encoding UTF8
Write-Host ($out | ConvertTo-Json -Compress)
Write-Host DONE
