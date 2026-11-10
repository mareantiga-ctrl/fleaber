# Follow-up probes + cleanup of disposable mint from independent audit.
$ErrorActionPreference = "Continue"
$envPath = Join-Path $PSScriptRoot "live_ops_staging.env"
Get-Content $envPath | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
  $k, $v = $_.Split('=', 2)
  Set-Item -Path "Env:$($k.Trim())" -Value $v.Trim()
}
$Base = "https://fxdknzrqjenzqcvnwqqq.supabase.co"
$Anon = $env:SUPABASE_ANON_KEY
$Svc  = $env:SUPABASE_SERVICE_ROLE_KEY
$Out  = Join-Path $PSScriptRoot "reports\AUDIT_CEGA_INDEP_PROBES_FOLLOWUP_2026-08-27.json"

function Auth($email, $pass) {
  Invoke-RestMethod -Method POST -Uri "$Base/auth/v1/token?grant_type=password" `
    -Headers @{ apikey = $Anon; Authorization = "Bearer $Anon" } `
    -ContentType "application/json" -Body (@{ email = $email; password = $pass } | ConvertTo-Json)
}
function H($tok) { @{ apikey = $Anon; Authorization = "Bearer $tok"; Prefer = "return=representation" } }
function SvcH { @{ apikey = $Anon; Authorization = "Bearer $Svc"; Prefer = "return=representation" } }

$buyer = Auth $env:LIVE_OPS_TEST_BUYER_EMAIL $env:LIVE_OPS_TEST_BUYER_PASSWORD
$seller = Auth $env:LIVE_OPS_TEST_SELLER_EMAIL $env:LIVE_OPS_TEST_SELLER_PASSWORD
$BT = $buyer.access_token; $ST = $seller.access_token
$BID = $buyer.user.id; $SID = $seller.user.id
$rows = @{}

function TryReq($name, $method, $uri, $headers, $body) {
  try {
    $p = @{ Method = $method; Uri = $uri; Headers = $headers; UseBasicParsing = $true }
    if ($null -ne $body) { $p.ContentType = "application/json"; $p.Body = $body }
    $r = Invoke-WebRequest @p
    $script:rows[$name] = @{ status = [int]$r.StatusCode; body = $r.Content.Substring(0, [Math]::Min(500, $r.Content.Length)) }
  } catch {
    $code = 0; $txt = $_.Exception.Message
    try { $code = [int]$_.Exception.Response.StatusCode; $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $txt = $sr.ReadToEnd() } catch {}
    $script:rows[$name] = @{ status = $code; body = $txt.Substring(0, [Math]::Min(500, $txt.Length)) }
  }
  Write-Host ("[{0}] {1} {2}" -f $name, $rows[$name].status, $rows[$name].body)
}

# product qty after mint orders
TryReq "product_qty" GET "$Base/rest/v1/products?id=eq.0892ca04-9c67-4990-9dad-02e0cf360811&select=id,quantity,is_sold,title" (H $ST) $null

# chats count / foreign ownership
TryReq "chats_foreign" GET "$Base/rest/v1/chats?select=id,user_a,user_b&user_a=neq.$BID&user_b=neq.$BID&limit=3" (H $BT) $null
TryReq "msgs_foreign" GET "$Base/rest/v1/chat_messages?select=id,chat_id,sender_id,text&sender_id=neq.$BID&limit=3" (H $BT) $null

# spoof message on a foreign chat
$chatId = "fa1a3f99-03b8-40fc-a923-7964a6dad586"
$spoof = @{ chat_id = $chatId; sender_id = $SID; receiver_id = $BID; text = "audit-cega-spoof" } | ConvertTo-Json -Compress
TryReq "spoof_msg" POST "$Base/rest/v1/chat_messages" (H $BT) $spoof

# review on someone else's order
$rev = @{ order_id = "d0972f17-ea2d-4457-a4ad-f720aec3f54b"; buyer_id = $BID; target_id = $SID; target_type = "seller"; stars = 5; author_role = "comprador"; comment = "audit-spoof-review" } | ConvertTo-Json -Compress
TryReq "spoof_review" POST "$Base/rest/v1/reviews" (H $BT) $rev

# lives without privileged cols
TryReq "lives_safe" GET "$Base/rest/v1/lives?select=id,status,seller_id&limit=2" (H $BT) $null
TryReq "lives_keys" GET "$Base/rest/v1/lives?select=id,mux_stream_key,stream_key&limit=1" (H $BT) $null
TryReq "lives_keys_seller" GET "$Base/rest/v1/lives?select=id,mux_stream_key,stream_key&limit=1" (H $ST) $null

# RPC curl named json
$rpcBody = @{ p_order_id = "eec1c79e-20cc-4fb8-8a5b-67e2650efafa" } | ConvertTo-Json -Compress
TryReq "rpc_release" POST "$Base/rest/v1/rpc/batata_release_seller_wallet_for_order" (H $BT) $rpcBody
$rpcPart = @{ p_order_id = "eec1c79e-20cc-4fb8-8a5b-67e2650efafa"; p_refund_percent = 100 } | ConvertTo-Json -Compress
TryReq "rpc_partial" POST "$Base/rest/v1/rpc/batata_process_partial_refund_dispute" (H $BT) $rpcPart
$rpcSys = @{ p_live_id = "00000000-0000-0000-0000-000000000001"; p_body = "x"; p_sender_label = "Sistema" } | ConvertTo-Json -Compress
TryReq "rpc_sysmsg" POST "$Base/rest/v1/rpc/batata_live_system_message" (H $BT) $rpcSys

# new order: pago -> concluido NO review, then dispute 100%
$ord = @{
  buyer_id = $BID; seller_id = $SID; product_id = "0892ca04-9c67-4990-9dad-02e0cf360811"
  quantity = 1; price_total = 1.11; status = "reserva_pendente"; payment_method = "MB WAY"
  shipping_method = "Levantamento em mao"
} | ConvertTo-Json -Compress
TryReq "disp_order" POST "$Base/rest/v1/orders" (H $BT) $ord

# parse last order id from body if possible
$dispOid = $null
try { $dispOid = ($rows.disp_order.body | ConvertFrom-Json)[0].id } catch {}
if ($dispOid) {
  TryReq "disp_pago" PATCH "$Base/rest/v1/orders?id=eq.$dispOid" (H $ST) (@{ status = "pago" } | ConvertTo-Json -Compress)
  TryReq "disp_conc" PATCH "$Base/rest/v1/orders?id=eq.$dispOid" (H $BT) (@{ status = "concluido" } | ConvertTo-Json -Compress)
  $dins = @{
    order_id = $dispOid; buyer_id = $BID; reason = "outro"; description = "audit-dispute"
    seller_refund_percent = 100; seller_offer_type = "partial_refund"
  } | ConvertTo-Json -Compress
  TryReq "disp_insert" POST "$Base/rest/v1/order_disputes" (H $BT) $dins
  TryReq "disp_rpc" POST "$Base/rest/v1/rpc/batata_process_partial_refund_dispute" (H $BT) ((@{ p_order_id = $dispOid; p_refund_percent = 1 } | ConvertTo-Json -Compress))
}

# wallets now
TryReq "w_buyer" GET "$Base/rest/v1/wallets?id=eq.$BID&select=id,balance" (H $BT) $null
TryReq "w_seller" GET "$Base/rest/v1/wallets?id=eq.$SID&select=id,balance" (H $ST) $null

# CPI with buyer_id+order_id no jwt
$cpi = @{ buyer_id = $BID; order_id = "eec1c79e-20cc-4fb8-8a5b-67e2650efafa"; amount = 50 } | ConvertTo-Json -Compress
TryReq "cpi_nojwt_meta" POST "$Base/functions/v1/create-payment-intent" @{ apikey = $Anon } $cpi

# anon products
TryReq "anon_products" GET "$Base/rest/v1/products?select=id,title,price&limit=2" @{ apikey = $Anon; Authorization = "Bearer $Anon" } $null

# connect payout as buyer tiny
TryReq "connect_payout" POST "$Base/functions/v1/create-connect-account" (H $BT) ((@{ action = "payout"; amount_cents = 100; idempotency_key = "audit-cega-no-payout-$(Get-Random)" } | ConvertTo-Json -Compress))

# CLEANUP disposable: revert phone, revert wallets to pre-probe (buyer 10.00, seller 10.90)
TryReq "cleanup_phone" PATCH "$Base/rest/v1/profiles?id=eq.$BID" (H $BT) (@{ phone_verified_at = $null } | ConvertTo-Json -Compress)
TryReq "cleanup_w_buyer" PATCH "$Base/rest/v1/wallets?id=eq.$BID" (SvcH) (@{ balance = 10.00 } | ConvertTo-Json -Compress)
TryReq "cleanup_w_seller" PATCH "$Base/rest/v1/wallets?id=eq.$SID" (SvcH) (@{ balance = 10.90 } | ConvertTo-Json -Compress)

$json = $rows | ConvertTo-Json -Depth 6
Set-Content -Path $Out -Encoding UTF8 -Value $json
Write-Host "WROTE $Out"
