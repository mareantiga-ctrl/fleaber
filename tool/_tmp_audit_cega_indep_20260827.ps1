# Independent blind-audit probes against Fleaber STAGING.
# Attacker = buyer/seller JWT + anon key. service_role used ONLY for observe/cleanup.
# Disposable data only. Does not patch application code.

$ErrorActionPreference = "Stop"
$envPath = Join-Path $PSScriptRoot "live_ops_staging.env"
Get-Content $envPath | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
  $k, $v = $_.Split('=', 2)
  Set-Item -Path "Env:$($k.Trim())" -Value $v.Trim()
}

$Base = "https://fxdknzrqjenzqcvnwqqq.supabase.co"
$Anon = $env:SUPABASE_ANON_KEY
$Svc  = $env:SUPABASE_SERVICE_ROLE_KEY
$Out  = Join-Path $PSScriptRoot "reports\AUDIT_CEGA_INDEP_PROBES_2026-08-27.json"
$findings = [System.Collections.Generic.List[object]]::new()

function Add-F($id, $ok, $detail) {
  $script:findings.Add([ordered]@{ id = $id; live = $true; result = $ok; detail = $detail })
  Write-Host ("[{0}] {1} :: {2}" -f $id, $ok, $detail)
}

function Auth-Password($email, $password) {
  $body = @{ email = $email; password = $password } | ConvertTo-Json
  $r = Invoke-RestMethod -Method POST -Uri "$Base/auth/v1/token?grant_type=password" `
    -Headers @{ apikey = $Anon; Authorization = "Bearer $Anon" } `
    -ContentType "application/json" -Body $body
  return $r
}

function Rest($method, $path, $token, $qs, $bodyObj, $prefer) {
  $headers = @{
    apikey = $Anon
    Authorization = "Bearer $token"
  }
  if ($prefer) { $headers["Prefer"] = $prefer }
  $uri = "$Base/rest/v1/$path"
  if ($qs) { $uri = "$uri`?$qs" }
  $params = @{ Method = $method; Uri = $uri; Headers = $headers }
  if ($null -ne $bodyObj) {
    $params.ContentType = "application/json"
    $params.Body = ($bodyObj | ConvertTo-Json -Depth 8 -Compress)
  }
  try {
    $resp = Invoke-WebRequest @params -UseBasicParsing
    return @{ status = [int]$resp.StatusCode; text = $resp.Content; ok = $true }
  } catch {
    $ex = $_.Exception.Response
    $code = 0
    $txt = $_.Exception.Message
    if ($ex) {
      $code = [int]$ex.StatusCode
      try {
        $sr = New-Object System.IO.StreamReader($ex.GetResponseStream())
        $txt = $sr.ReadToEnd()
      } catch {}
    }
    return @{ status = $code; text = $txt; ok = $false }
  }
}

function Rpc($name, $token, $args) {
  return Rest POST "rpc/$name" $token $null $args $null
}

function Edge($fn, $method, $token, $qs, $bodyObj) {
  $uri = "$Base/functions/v1/$fn"
  if ($qs) { $uri = "$uri`?$qs" }
  $headers = @{ apikey = $Anon }
  if ($token) { $headers.Authorization = "Bearer $token" }
  $params = @{ Method = $method; Uri = $uri; Headers = $headers }
  if ($null -ne $bodyObj) {
    $params.ContentType = "application/json"
    $params.Body = ($bodyObj | ConvertTo-Json -Depth 8 -Compress)
  }
  try {
    $resp = Invoke-WebRequest @params -UseBasicParsing
    return @{ status = [int]$resp.StatusCode; text = $resp.Content; ok = $true }
  } catch {
    $ex = $_.Exception.Response
    $code = 0
    $txt = $_.Exception.Message
    if ($ex) {
      $code = [int]$ex.StatusCode
      try {
        $sr = New-Object System.IO.StreamReader($ex.GetResponseStream())
        $txt = $sr.ReadToEnd()
      } catch {}
    }
    return @{ status = $code; text = $txt; ok = $false }
  }
}

function Parse-Json($text) {
  if (-not $text) { return $null }
  try { return $text | ConvertFrom-Json } catch { return $null }
}

Write-Host "=== login ==="
$buyerAuth = Auth-Password $env:LIVE_OPS_TEST_BUYER_EMAIL $env:LIVE_OPS_TEST_BUYER_PASSWORD
$sellerAuth = Auth-Password $env:LIVE_OPS_TEST_SELLER_EMAIL $env:LIVE_OPS_TEST_SELLER_PASSWORD
$BT = $buyerAuth.access_token
$ST = $sellerAuth.access_token
$BID = $buyerAuth.user.id
$SID = $sellerAuth.user.id
Write-Host "buyer=$BID seller=$SID"

# --- A1 anon / JWT identity ---
$anonProfiles = Rest GET "profiles" $Anon "select=id&limit=5" $null $null
Add-F "A1_anon_profiles" $(if ($anonProfiles.status -ge 400 -or $anonProfiles.text -eq "[]") { "BLOCKED" } else { "OPEN" }) `
  "status=$($anonProfiles.status) len=$($anonProfiles.text.Length) sample=$($anonProfiles.text.Substring(0, [Math]::Min(180, $anonProfiles.text.Length)))"

$buyerOtherProfiles = Rest GET "profiles" $BT "select=id,full_name,user_type,phone,phone_verified_at&limit=8" $null $null
Add-F "A2_buyer_profiles_scope" $(if ($buyerOtherProfiles.text -match $SID) { "CROSS_USER" } else { "OWN_OR_EMPTY" }) `
  "status=$($buyerOtherProfiles.status) body=$($buyerOtherProfiles.text.Substring(0, [Math]::Min(400, $buyerOtherProfiles.text.Length)))"

$buyerWallets = Rest GET "wallets" $BT "select=id,balance" $null $null
Add-F "A3_buyer_wallets" "INFO" "status=$($buyerWallets.status) body=$($buyerWallets.text)"

$buyerOtherWallet = Rest GET "wallets" $BT "id=eq.$SID&select=id,balance" $null $null
Add-F "A4_buyer_read_seller_wallet" $(if ($buyerOtherWallet.text -eq "[]" -or $buyerOtherWallet.status -ge 400) { "BLOCKED" } else { "OPEN" }) `
  "status=$($buyerOtherWallet.status) body=$($buyerOtherWallet.text)"

$credit = Rpc "batata_credit_wallet_once" $BT @{ p_wallet_id = $BID; p_order_id = "00000000-0000-0000-0000-000000000001"; p_amount = 99.0; p_type = "reembolso"; p_description = "audit" }
Add-F "A5_credit_wallet_once_jwt" $(if ($credit.status -ge 400) { "BLOCKED" } else { "OPEN" }) `
  "status=$($credit.status) body=$($credit.text)"

$payout = Rpc "batata_wallet_payout_debit" $BT @{ p_user_id = $BID; p_amount_cents = 100; p_idempotency_key = "auditcega-$(Get-Random)" }
Add-F "A6_payout_debit_jwt" $(if ($payout.status -ge 400) { "BLOCKED" } else { "OPEN" }) `
  "status=$($payout.status) body=$($payout.text)"

$adminSelf = Rest PATCH "profiles" $BT "id=eq.$BID" @{ user_type = "admin" } "return=representation"
Add-F "A7_self_admin" $(if ($adminSelf.text -match '"user_type":"admin"') { "OPEN" } else { "BLOCKED_OR_STRIPPED" }) `
  "status=$($adminSelf.status) body=$($adminSelf.text.Substring(0, [Math]::Min(300, $adminSelf.text.Length)))"

$phoneVer = Rest PATCH "profiles" $BT "id=eq.$BID" @{ phone_verified_at = (Get-Date).ToUniversalTime().ToString("o") } "return=representation"
Add-F "A8_phone_verified_at" $(if ($phoneVer.text -match "phone_verified_at" -and $phoneVer.ok) { "WRITABLE" } else { "BLOCKED_OR_NOCOL" }) `
  "status=$($phoneVer.status) body=$($phoneVer.text.Substring(0, [Math]::Min(300, $phoneVer.text.Length)))"

# --- chats / reviews / messages ---
$chats = Rest GET "chats" $BT "select=id,user_a,user_b,product_id&limit=20" $null $null
Add-F "B1_chats_select" "INFO" "status=$($chats.status) count_hint=$($chats.text.Length) sample=$($chats.text.Substring(0, [Math]::Min(250, $chats.text.Length)))"

$msgs = Rest GET "chat_messages" $BT "select=id,chat_id,sender_id,text,receiver_id&limit=8" $null $null
Add-F "B2_chat_messages_select" "INFO" "status=$($msgs.status) sample=$($msgs.text.Substring(0, [Math]::Min(350, $msgs.text.Length)))"

$reviews = Rest GET "reviews" $BT "select=id,order_id,stars,author_role,buyer_id&limit=8" $null $null
Add-F "B3_reviews_select" "INFO" "status=$($reviews.status) sample=$($reviews.text.Substring(0, [Math]::Min(250, $reviews.text.Length)))"

# --- orders: create disposable product + order ---
$prodBody = @{
  seller_id = $SID
  title = "AUDIT-CEGA-DISP-$(Get-Random)"
  price = 1.00
  quantity = 3
  list_on_marketplace = $false
  available_for_live = $false
  is_sold = $false
}
$prod = Rest POST "products" $ST $null $prodBody "return=representation"
$prodJson = Parse-Json $prod.text
$ProdId = $null
if ($prodJson -is [array]) { $ProdId = $prodJson[0].id } else { $ProdId = $prodJson.id }
Add-F "C0_seller_create_product" $(if ($ProdId) { "OK" } else { "FAIL" }) "status=$($prod.status) pid=$ProdId body=$($prod.text.Substring(0, [Math]::Min(200, $prod.text.Length)))"

# buyer insert inflated price + stripe ids
$orderInflated = @{
  buyer_id = $BID
  seller_id = $SID
  product_id = $ProdId
  quantity = 1
  price_total = 777.77
  status = "pago"
  payment_method = "MB WAY"
  shipping_method = "Levantamento em mao"
  stripe_payment_intent_id = "pi_fake_audit"
  stripe_checkout_session_id = "cs_fake_audit"
  amount_paid_cents = 77777
}
$insPaid = Rest POST "orders" $BT $null $orderInflated "return=representation"
$insPaidJ = Parse-Json $insPaid.text
$OID1 = $null
if ($insPaidJ -is [array]) { $OID1 = $insPaidJ[0].id } else { $OID1 = $insPaidJ.id }
$st1 = if ($insPaidJ -is [array]) { $insPaidJ[0].status } else { $insPaidJ.status }
$pi1 = if ($insPaidJ -is [array]) { $insPaidJ[0].stripe_payment_intent_id } else { $insPaidJ.stripe_payment_intent_id }
$amt1 = if ($insPaidJ -is [array]) { $insPaidJ[0].amount_paid_cents } else { $insPaidJ.amount_paid_cents }
$pt1 = if ($insPaidJ -is [array]) { $insPaidJ[0].price_total } else { $insPaidJ.price_total }
Add-F "C1_buyer_insert_pago_stripe" "INFO" "status_http=$($insPaid.status) oid=$OID1 status=$st1 pi=$pi1 amount_paid=$amt1 price=$pt1"

# buyer self-mark pago from reserva
$orderNorm = @{
  buyer_id = $BID
  seller_id = $SID
  product_id = $ProdId
  quantity = 1
  price_total = 2.00
  status = "reserva_pendente"
  payment_method = "MB WAY"
  shipping_method = "Levantamento em mao"
}
$ins2 = Rest POST "orders" $BT $null $orderNorm "return=representation"
$ins2J = Parse-Json $ins2.text
$OID2 = if ($ins2J -is [array]) { $ins2J[0].id } else { $ins2J.id }
$patchPagoBuyer = Rest PATCH "orders" $BT "id=eq.$OID2" @{ status = "pago" } "return=representation"
$ppb = Parse-Json $patchPagoBuyer.text
$stBuyerPago = if ($ppb -is [array]) { $ppb[0].status } else { $ppb.status }
Add-F "C2_buyer_self_pago" $(if ($stBuyerPago -eq "pago") { "OPEN" } else { "BLOCKED" }) `
  "http=$($patchPagoBuyer.status) status=$stBuyerPago body=$($patchPagoBuyer.text.Substring(0, [Math]::Min(220, $patchPagoBuyer.text.Length)))"

# seller mark pago (MB WAY path)
$patchPagoSeller = Rest PATCH "orders" $ST "id=eq.$OID2" @{ status = "pago" } "return=representation"
$pps = Parse-Json $patchPagoSeller.text
$stSellerPago = if ($pps -is [array]) { $pps[0].status } else { $pps.status }
$stockApplied = if ($pps -is [array]) { $pps[0].stock_units_applied } else { $pps.stock_units_applied }
Add-F "C3_seller_mark_pago" "INFO" "http=$($patchPagoSeller.status) status=$stSellerPago stock_units=$stockApplied body=$($patchPagoSeller.text.Substring(0, [Math]::Min(280, $patchPagoSeller.text.Length)))"

# wallet before
$wBefore = Rest GET "wallets" $BT "id=eq.$BID&select=id,balance" $null $null
Add-F "C4_wallet_before_devolvida" "INFO" $wBefore.text

# seller mark devolvida
$patchDev = Rest PATCH "orders" $ST "id=eq.$OID2" @{ status = "devolvida" } "return=representation"
$pd = Parse-Json $patchDev.text
$stDev = if ($pd -is [array]) { $pd[0].status } else { $pd.status }
$wrp = if ($pd -is [array]) { $pd[0].wallet_refund_processed_at } else { $pd.wallet_refund_processed_at }
Add-F "C5_seller_mark_devolvida" "INFO" "http=$($patchDev.status) status=$stDev refund_at=$wrp body=$($patchDev.text.Substring(0, [Math]::Min(320, $patchDev.text.Length)))"

Start-Sleep -Seconds 1
$wAfter = Rest GET "wallets" $BT "id=eq.$BID&select=id,balance" $null $null
Add-F "C6_wallet_after_devolvida" "INFO" $wAfter.text

$tx = Rest GET "wallet_transactions" $BT "order_id=eq.$OID2&select=id,amount,type,description,order_id" $null $null
Add-F "C7_wallet_tx_for_order" "INFO" $tx.text

# buyer concluido + review mint path on a NEW order
$ins3 = Rest POST "orders" $BT $null $orderNorm "return=representation"
$ins3J = Parse-Json $ins3.text
$OID3 = if ($ins3J -is [array]) { $ins3J[0].id } else { $ins3J.id }
$null = Rest PATCH "orders" $ST "id=eq.$OID3" @{ status = "pago" } "return=representation"
$patchConc = Rest PATCH "orders" $BT "id=eq.$OID3" @{ status = "concluido" } "return=representation"
$pc = Parse-Json $patchConc.text
$stConc = if ($pc -is [array]) { $pc[0].status } else { $pc.status }
Add-F "C8_buyer_concluido_from_pago" $(if ($stConc -eq "concluido") { "OPEN" } else { "BLOCKED" }) `
  "http=$($patchConc.status) status=$stConc"

$wSellerBefore = Rest GET "wallets" $ST "id=eq.$SID&select=id,balance" $null $null
Add-F "C9_seller_wallet_before_review" "INFO" $wSellerBefore.text

$revIns = Rest POST "reviews" $BT $null @{
  order_id = $OID3
  buyer_id = $BID
  target_id = $SID
  target_type = "seller"
  stars = 5
  author_role = "comprador"
  comment = "audit-cega-disposable"
} "return=representation"
Add-F "C10_buyer_insert_review" "INFO" "http=$($revIns.status) body=$($revIns.text.Substring(0, [Math]::Min(280, $revIns.text.Length)))"

Start-Sleep -Seconds 1
$rel = Rpc "batata_release_seller_wallet_for_order" $BT @{ p_order_id = $OID3 }
Add-F "C11_release_wallet_rpc" "INFO" "http=$($rel.status) body=$($rel.text)"
$wSellerAfter = Rest GET "wallets" $ST "id=eq.$SID&select=id,balance" $null $null
Add-F "C12_seller_wallet_after_review" "INFO" $wSellerAfter.text

# --- dispute percent ---
# need post-pay + concluido/entregue for insert. Use OID3 if concluido.
$dispIns = Rest POST "order_disputes" $BT $null @{
  order_id = $OID3
  buyer_id = $BID
  reason = "outro"
  description = "audit-cega-disposable"
  seller_refund_percent = 100
  seller_offer_type = "partial_refund"
} "return=representation"
Add-F "D1_dispute_insert" "INFO" "http=$($dispIns.status) body=$($dispIns.text.Substring(0, [Math]::Min(320, $dispIns.text.Length)))"
$dispJ = Parse-Json $dispIns.text
$DID = $null
if ($dispJ -is [array]) { $DID = $dispJ[0].id } else { $DID = $dispJ.id }

if ($DID) {
  $dispPatch = Rest PATCH "order_disputes" $BT "id=eq.$DID" @{ seller_refund_percent = 100; seller_offer_type = "partial_refund" } "return=representation"
  Add-F "D2_buyer_patch_refund_percent" "INFO" "http=$($dispPatch.status) body=$($dispPatch.text.Substring(0, [Math]::Min(280, $dispPatch.text.Length)))"
  $part = Rpc "batata_process_partial_refund_dispute" $BT @{ p_order_id = $OID3; p_refund_percent = 100 }
  Add-F "D3_partial_refund_rpc" "INFO" "http=$($part.status) body=$($part.text)"
} else {
  # try patch any existing dispute the buyer can see
  $existD = Rest GET "order_disputes" $BT "select=id,order_id,seller_refund_percent,status&limit=3" $null $null
  Add-F "D1b_existing_disputes" "INFO" $existD.text
}

# --- raffle forge ---
$raffleOrder = Rest POST "orders" $BT $null @{
  buyer_id = $BID
  seller_id = $SID
  product_id = $ProdId
  quantity = 1
  price_total = 0
  status = "premio_rifa"
  payment_method = "Premio rifa"
  live_raffle_id = "00000000-0000-0000-0000-000000000099"
} "return=representation"
$ro = Parse-Json $raffleOrder.text
$rst = if ($ro -is [array]) { $ro[0].status } else { $ro.status }
$rrid = if ($ro -is [array]) { $ro[0].live_raffle_id } else { $ro.live_raffle_id }
Add-F "E1_forge_premio_rifa" $(if ($rst -eq "premio_rifa") { "OPEN" } else { "BLOCKED_OR_STRIPPED" }) `
  "http=$($raffleOrder.status) status=$rst raffle=$rrid body=$($raffleOrder.text.Substring(0, [Math]::Min(250, $raffleOrder.text.Length)))"

$draw = Rpc "batata_draw_live_raffle_winners" $BT @{ p_raffle_id = "00000000-0000-0000-0000-000000000099" }
Add-F "E2_buyer_draw_raffle" $(if ($draw.status -ge 400 -or $draw.text -match "not_allowed|false") { "BLOCKED" } else { "OPEN_OR_NOOP" }) `
  "http=$($draw.status) body=$($draw.text.Substring(0, [Math]::Min(200, $draw.text.Length)))"

$prize = Rpc "batata_create_raffle_prize_order" $BT @{ p_raffle_id = "00000000-0000-0000-0000-000000000099" }
Add-F "E3_buyer_create_prize_order" $(if ($prize.status -ge 400) { "BLOCKED" } else { "OPEN" }) `
  "http=$($prize.status) body=$($prize.text.Substring(0, [Math]::Min(200, $prize.text.Length)))"

# --- edges ---
$cpiGet = Edge "create-payment-intent" GET $null "session_id=cs_test_fake_auditcega&checkout_return=success" $null
Add-F "F1_settle_get_fake_session" "INFO" "http=$($cpiGet.status) body=$($cpiGet.text.Substring(0, [Math]::Min(220, $cpiGet.text.Length)))"

$cpiPostNoJwt = Edge "create-payment-intent" POST $null $null @{ order_id = $OID2; amount = 1 }
Add-F "F2_cpi_post_no_jwt" $(if ($cpiPostNoJwt.status -ge 400) { "BLOCKED" } else { "OPEN" }) `
  "http=$($cpiPostNoJwt.status) body=$($cpiPostNoJwt.text.Substring(0, [Math]::Min(220, $cpiPostNoJwt.text.Length)))"

$cpiUnder = Edge "create-payment-intent" POST $BT $null @{ order_id = $OID1; amount = 50; product_id = $ProdId }
Add-F "F3_cpi_post_buyer_inflated_order" "INFO" "http=$($cpiUnder.status) body=$($cpiUnder.text.Substring(0, [Math]::Min(400, $cpiUnder.text.Length)))"

$refBuyer = Edge "refund-order" POST $BT $null @{ order_id = $OID2 }
Add-F "F4_refund_as_buyer" $(if ($refBuyer.status -eq 403 -or $refBuyer.text -match "permiss") { "BLOCKED" } else { "CHECK" }) `
  "http=$($refBuyer.status) body=$($refBuyer.text.Substring(0, [Math]::Min(220, $refBuyer.text.Length)))"

$wh = Edge "stripe-webhook" POST $null $null @{ type = "checkout.session.completed" }
Add-F "F5_webhook_no_sig" $(if ($wh.status -ge 400) { "BLOCKED" } else { "OPEN" }) `
  "http=$($wh.status) body=$($wh.text.Substring(0, [Math]::Min(200, $wh.text.Length)))"

$ocr = Edge "ingest-ocr-reservation" POST $null $null @{ live_id = "00000000-0000-0000-0000-000000000001"; requested_qty = 1 }
Add-F "F6_ocr_no_device_token" $(if ($ocr.status -ge 400) { "BLOCKED" } else { "OPEN" }) `
  "http=$($ocr.status) body=$($ocr.text.Substring(0, [Math]::Min(220, $ocr.text.Length)))"

$pair = Edge "ps-pairing-claim" POST $null $null @{ code = "000000" }
Add-F "F7_pairing_guess" "INFO" "http=$($pair.status) body=$($pair.text.Substring(0, [Math]::Min(200, $pair.text.Length)))"

$cleanup = Edge "livekit-egress-cleanup" POST $Anon $null @{ }
Add-F "F8_egress_cleanup_anon" $(if ($cleanup.status -ge 400) { "BLOCKED" } else { "OPEN" }) `
  "http=$($cleanup.status) body=$($cleanup.text.Substring(0, [Math]::Min(180, $cleanup.text.Length)))"

$e2e = Edge "create-payment-intent" POST $BT "fase2_e2e_settle=1" @{ order_id = $OID2; payment_intent_id = "pi_x" }
Add-F "F9_fase2_e2e_settle_jwt" $(if ($e2e.status -ge 400) { "BLOCKED" } else { "OPEN" }) `
  "http=$($e2e.status) body=$($e2e.text.Substring(0, [Math]::Min(220, $e2e.text.Length)))"

$sys = Rpc "batata_live_system_message" $BT @{ p_live_id = "00000000-0000-0000-0000-000000000001"; p_body = "audit"; p_sender_label = "Sistema" }
Add-F "G1_system_message_buyer" "INFO" "http=$($sys.status) body=$($sys.text.Substring(0, [Math]::Min(220, $sys.text.Length)))"

$ensure = Rpc "batata_ensure_checkout_product" $BT @{ p_live_item_id = "00000000-0000-0000-0000-000000000001" }
Add-F "G2_ensure_checkout_fake_item" "INFO" "http=$($ensure.status) body=$($ensure.text.Substring(0, [Math]::Min(220, $ensure.text.Length)))"

$emailFind = Rpc "batata_find_user_id_by_email" $BT @{ p_email = $env:LIVE_OPS_TEST_SELLER_EMAIL }
Add-F "G3_find_user_by_email" "INFO" "http=$($emailFind.status) body=$($emailFind.text.Substring(0, [Math]::Min(180, $emailFind.text.Length)))"

# cross-user order read
$otherOrders = Rest GET "orders" $BT "select=id,buyer_id,seller_id,price_total&buyer_id=neq.$BID&limit=5" $null $null
Add-F "H1_buyer_orders_not_party" $(if ($otherOrders.text -eq "[]") { "BLOCKED" } else { "CHECK" }) `
  "http=$($otherOrders.status) body=$($otherOrders.text.Substring(0, [Math]::Min(220, $otherOrders.text.Length)))"

# lives stream keys
$lives = Rest GET "lives" $BT "select=id,mux_stream_key,stream_key,mux_playback_id&limit=3" $null $null
Add-F "H2_lives_stream_keys" "INFO" "http=$($lives.status) body=$($lives.text.Substring(0, [Math]::Min(300, $lives.text.Length)))"

# storage list
$stor = Invoke-WebRequest -Method GET -Uri "$Base/storage/v1/object/list/chat_media" `
  -Headers @{ apikey = $Anon; Authorization = "Bearer $BT" } `
  -ContentType "application/json" -Body '{"prefix":"","limit":5}' -UseBasicParsing -ErrorAction SilentlyContinue
Add-F "H3_storage_list_chat_media" "INFO" "http=$($stor.StatusCode) body=$($stor.Content.Substring(0, [Math]::Min(200, $stor.Content.Length)))"

# cancel post-pay as buyer if still pago on OID1
if ($OID1) {
  $can = Rest PATCH "orders" $BT "id=eq.$OID1" @{ status = "cancelado" } "return=representation"
  $cj = Parse-Json $can.text
  $cst = if ($cj -is [array]) { $cj[0].status } else { $cj.status }
  Add-F "C13_buyer_cancel_after_insert" "INFO" "http=$($can.status) status=$cst"
}

# spoof chat message as seller
$spoofMsg = Rest POST "chat_messages" $BT $null @{
  chat_id = "00000000-0000-0000-0000-000000000001"
  sender_id = $SID
  receiver_id = $BID
  text = "audit-cega-spoof-as-seller"
} "return=representation"
Add-F "B4_spoof_chat_sender" "INFO" "http=$($spoofMsg.status) body=$($spoofMsg.text.Substring(0, [Math]::Min(280, $spoofMsg.text.Length)))"

# revert phone_verified_at mutation on disposable test profile
$revertPhone = Rest PATCH "profiles" $BT "id=eq.$BID" @{ phone_verified_at = $null } "return=representation"
Add-F "Z1_revert_phone_verified" "INFO" "http=$($revertPhone.status) body=$($revertPhone.text.Substring(0, [Math]::Min(180, $revertPhone.text.Length)))"

# Observe deployed function grants via service_role (observe only)
$obsSql = @"
select p.proname, pg_get_function_identity_arguments(p.oid) as args,
       p.prosecdef as security_definer
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'batata_orders_guard_paid_status','batata_refund_buyer_wallet_for_order',
  'batata_process_partial_refund_dispute','batata_live_item_total_qty',
  'batata_mark_product_sold_on_paid_order','batata_credit_wallet_once'
);
"@
# PostgREST cannot run arbitrary SQL. Skip.

# Cleanup: cancel leftover disposable orders as seller if still pre-pay; leave minted wallets for report then revert via svc if minted.
$payload = [ordered]@{
  ts = (Get-Date).ToUniversalTime().ToString("o")
  buyer = $BID
  seller = $SID
  product_id = $ProdId
  order_insert_pago = $OID1
  order_mint_path = $OID2
  order_concluido_path = $OID3
  findings = $findings
}
$dir = Split-Path $Out
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$payload | ConvertTo-Json -Depth 8 | Set-Content -Path $Out -Encoding UTF8
Write-Host "WROTE $Out"
Write-Host "DONE"
