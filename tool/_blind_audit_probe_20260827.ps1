# Blind audit probes — JWT attacker only. Disposable data. No app changes.
$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot 'live_ops_staging.env'
Get-Content $envFile | ForEach-Object {
  $line = $_.Trim()
  if ($line -eq '' -or $line.StartsWith('#')) { return }
  $eq = $line.IndexOf('=')
  if ($eq -lt 1) { return }
  $k = $line.Substring(0, $eq).Trim()
  $v = $line.Substring($eq + 1).Trim()
  Set-Item -Path "Env:$k" -Value $v
}

$Base = ($env:SUPABASE_URL -replace '/rest/v1/?$', '')
$Anon = $env:SUPABASE_ANON_KEY
$BuyerEmail = $env:LIVE_OPS_TEST_BUYER_EMAIL
$BuyerPass = $env:LIVE_OPS_TEST_BUYER_PASSWORD
$SellerEmail = $env:LIVE_OPS_TEST_SELLER_EMAIL
$SellerPass = $env:LIVE_OPS_TEST_SELLER_PASSWORD
$BuyerId = $env:LIVE_OPS_TEST_BUYER_ID
$SellerId = $env:LIVE_OPS_TEST_SELLER_ID
$Fn = "$Base/functions/v1"
$Rest = "$Base/rest/v1"
$Out = @()

function Add-Finding($id, $ok, $detail) {
  $script:Out += [pscustomobject]@{ id = $id; ok = $ok; detail = ($detail -replace '\s+', ' ').Substring(0, [Math]::Min(500, (($detail -replace '\s+', ' ').Length))) }
  Write-Host ("[{0}] {1}  {2}" -f $(if ($ok) { 'HOLD' } else { 'OPEN' }), $id, $detail.Substring(0, [Math]::Min(180, $detail.Length)))
}

function Invoke-Api {
  param($Method, $Url, $Headers, $Body, $Query)
  $h = @{ apikey = $Anon; Accept = 'application/json' }
  if ($Headers) { $Headers.GetEnumerator() | ForEach-Object { $h[$_.Key] = $_.Value } }
  $params = @{ Method = $Method; Uri = $Url; Headers = $h; TimeoutSec = 45 }
  if ($null -ne $Body) {
    $params.ContentType = 'application/json'
    $params.Body = ($Body | ConvertTo-Json -Depth 12 -Compress)
  }
  try {
    $resp = Invoke-WebRequest @params
    return @{ status = [int]$resp.StatusCode; text = $resp.Content }
  } catch {
    $r = $_.Exception.Response
    if ($r) {
      $reader = New-Object System.IO.StreamReader($r.GetResponseStream())
      $txt = $reader.ReadToEnd()
      return @{ status = [int]$r.StatusCode; text = $txt }
    }
    return @{ status = 0; text = $_.Exception.Message }
  }
}

function Sign-In($email, $pass) {
  $r = Invoke-Api POST "$Base/auth/v1/token?grant_type=password" @{ apikey = $Anon } @{ email = $email; password = $pass }
  if ($r.status -ne 200) { throw "login failed $email $($r.status) $($r.text)" }
  $j = $r.text | ConvertFrom-Json
  return $j.access_token
}

function AuthH($jwt) {
  return @{ Authorization = "Bearer $jwt"; apikey = $Anon; Prefer = 'return=representation' }
}

Write-Host "Signing in..."
$buyerJwt = Sign-In $BuyerEmail $BuyerPass
$sellerJwt = Sign-In $SellerEmail $SellerPass
$strangerEmail = "blind-audit-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())@fleaber.test"
$strangerPass = 'TesteTeste1!'
$reg = Invoke-Api POST "$Base/auth/v1/signup" @{ apikey = $Anon } @{ email = $strangerEmail; password = $strangerPass }
$strangerJwt = $null
$strangerId = $null
if ($reg.status -eq 200) {
  $rj = $reg.text | ConvertFrom-Json
  $strangerJwt = $rj.access_token
  $strangerId = $rj.user.id
  if (-not $strangerJwt) { $strangerJwt = Sign-In $strangerEmail $strangerPass }
}

# --- Anon probes ---
$anonWallets = Invoke-Api GET "$Rest/wallets?select=id,balance&limit=3" @{ apikey = $Anon }
Add-Finding 'anon_wallets' ($anonWallets.status -ge 400 -or $anonWallets.text -eq '[]' -or $anonWallets.text -eq '') "anon wallets HTTP $($anonWallets.status) body=$($anonWallets.text.Substring(0,[Math]::Min(80,$anonWallets.text.Length)))"

$anonOrders = Invoke-Api GET "$Rest/orders?select=id,price_total,buyer_id&limit=3" @{ apikey = $Anon }
Add-Finding 'anon_orders' ($anonOrders.status -ge 400 -or $anonOrders.text -eq '[]') "anon orders HTTP $($anonOrders.status) len=$($anonOrders.text.Length)"

$anonProfiles = Invoke-Api GET "$Rest/profiles?select=id,email,phone,mb_way,iban,user_type&limit=5" @{ apikey = $Anon }
$anonProfHold = ($anonProfiles.text -eq '[]' -or $anonProfiles.status -ge 400)
Add-Finding 'anon_profiles_pii' $anonProfHold "anon profiles HTTP $($anonProfiles.status) sample=$($anonProfiles.text.Substring(0,[Math]::Min(120,$anonProfiles.text.Length)))"

$anonLives = Invoke-Api GET "$Rest/lives?select=id,mux_stream_key,stream_key&limit=2" @{ apikey = $Anon }
$livesHasKey = $anonLives.text -match 'mux_stream_key":"[^"]+"' -or $anonLives.text -match 'stream_key":"[^n"][^"]+"'
Add-Finding 'anon_stream_keys' (-not $livesHasKey) "anon lives HTTP $($anonLives.status) keys_exposed=$livesHasKey body=$($anonLives.text.Substring(0,[Math]::Min(100,$anonLives.text.Length)))"

# --- Cross-user ---
$buyerOtherOrders = Invoke-Api GET "$Rest/orders?select=id,buyer_id,seller_id,price_total,status&seller_id=eq.$SellerId&buyer_id=neq.$BuyerId&limit=5" (AuthH $buyerJwt)
$cross = $false
try { $arr = $buyerOtherOrders.text | ConvertFrom-Json; if ($arr -is [array] -and $arr.Count -gt 0) { $cross = $true } elseif ($arr.id) { $cross = $true } } catch {}
Add-Finding 'buyer_cross_orders' (-not $cross) "buyer other-seller-orders HTTP $($buyerOtherOrders.status) cross=$cross"

$buyerSellerWallet = Invoke-Api GET "$Rest/wallets?select=id,balance&id=eq.$SellerId" (AuthH $buyerJwt)
$sawSellerWallet = $buyerSellerWallet.text -match $SellerId
Add-Finding 'buyer_read_seller_wallet' (-not $sawSellerWallet) "HTTP $($buyerSellerWallet.status) body=$($buyerSellerWallet.text.Substring(0,[Math]::Min(80,$buyerSellerWallet.text.Length)))"

$buyerCredit = Invoke-Api POST "$Rest/rpc/batata_credit_wallet_once" (AuthH $buyerJwt) @{ p_user_id = $BuyerId; p_order_id = '00000000-0000-0000-0000-000000000001'; p_amount = 99; p_type = 'venda'; p_description = 'audit' }
Add-Finding 'jwt_credit_wallet' ($buyerCredit.status -ge 400) "credit_wallet_once HTTP $($buyerCredit.status) $($buyerCredit.text.Substring(0,[Math]::Min(140,$buyerCredit.text.Length)))"

$buyerEnsureOther = Invoke-Api POST "$Rest/rpc/batata_ensure_wallet" (AuthH $buyerJwt) @{ p_user_id = $SellerId }
Add-Finding 'jwt_ensure_wallet_other' ($buyerEnsureOther.status -ge 400) "ensure_wallet HTTP $($buyerEnsureOther.status) $($buyerEnsureOther.text.Substring(0,[Math]::Min(140,$buyerEnsureOther.text.Length)))"

$buyerConvert = Invoke-Api POST "$Rest/rpc/batata_live_reservation_stripe_convert" (AuthH $buyerJwt) @{ p_request_id = '00000000-0000-0000-0000-000000000001'; p_order_id = '00000000-0000-0000-0000-000000000001' }
Add-Finding 'jwt_stripe_convert' ($buyerConvert.status -ge 400) "stripe_convert HTTP $($buyerConvert.status) $($buyerConvert.text.Substring(0,[Math]::Min(140,$buyerConvert.text.Length)))"

$buyerAdmin = Invoke-Api PATCH "$Rest/profiles?id=eq.$BuyerId" (AuthH $buyerJwt) @{ user_type = 'admin' }
$afterAdmin = Invoke-Api GET "$Rest/profiles?select=id,user_type&id=eq.$BuyerId" (AuthH $buyerJwt)
$isAdmin = $afterAdmin.text -match '"user_type":"admin'
Add-Finding 'self_promote_admin' (-not $isAdmin) "PATCH $($buyerAdmin.status) after=$($afterAdmin.text.Substring(0,[Math]::Min(80,$afterAdmin.text.Length)))"

# --- Seller creates disposable product ---
$tag = "BLIND_AUDIT_$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
$prodBody = @{
  seller_id = $SellerId
  title = $tag
  price = 12.00
  quantity = 3
  list_on_marketplace = $false
  available_for_live = $false
  image_urls = @()
  description = 'disposable audit product'
}
$prod = Invoke-Api POST "$Rest/products" (AuthH $sellerJwt) $prodBody
$productId = $null
try { $productId = ($prod.text | ConvertFrom-Json).id } catch {}
if (-not $productId) {
  Add-Finding 'create_product' $false "seller insert product HTTP $($prod.status) $($prod.text.Substring(0,[Math]::Min(200,$prod.text.Length)))"
} else {
  Add-Finding 'create_product' $true "product=$productId"
}

$orderId = $null
if ($productId) {
  $ord = Invoke-Api POST "$Rest/orders" (AuthH $buyerJwt) @{
    product_id = $productId
    buyer_id = $BuyerId
    seller_id = $SellerId
    price_total = 1.00
    quantity = 1
    status = 'pago'
    payment_method = 'Pagamento na app'
    shipping_method = 'hand'
  }
  try { $orderId = ($ord.text | ConvertFrom-Json).id } catch {}
  $st = ''
  try { $st = ($ord.text | ConvertFrom-Json).status } catch {}
  Add-Finding 'insert_status_pago' ($st -ne 'pago' -and $null -ne $orderId) "insert HTTP $($ord.status) status=$st id=$orderId body=$($ord.text.Substring(0,[Math]::Min(160,$ord.text.Length)))"
}

if ($orderId) {
  $upPrice = Invoke-Api PATCH "$Rest/orders?id=eq.$orderId" (AuthH $buyerJwt) @{ price_total = 0.50 }
  $read = Invoke-Api GET "$Rest/orders?select=id,price_total,status,quantity&id=eq.$orderId" (AuthH $buyerJwt)
  $pt = 0
  try { $pt = [decimal]($read.text | ConvertFrom-Json).price_total } catch {}
  Add-Finding 'jwt_price_total_freeze' ($pt -ne 0.50) "after patch price_total=$pt HTTP $($upPrice.status) $($read.text.Substring(0,[Math]::Min(120,$read.text.Length)))"

  $upPago = Invoke-Api PATCH "$Rest/orders?id=eq.$orderId" (AuthH $buyerJwt) @{ status = 'pago' }
  $read2 = Invoke-Api GET "$Rest/orders?select=status&id=eq.$orderId" (AuthH $buyerJwt)
  $st2 = ''
  try { $st2 = ($read2.text | ConvertFrom-Json).status } catch {}
  Add-Finding 'buyer_self_pago' ($st2 -ne 'pago') "buyer PATCH pago -> status=$st2 HTTP $($upPago.status)"

  $upQty = Invoke-Api PATCH "$Rest/orders?id=eq.$orderId" (AuthH $buyerJwt) @{ quantity = 3 }
  $read3 = Invoke-Api GET "$Rest/orders?select=quantity,status&id=eq.$orderId" (AuthH $buyerJwt)
  $qty = 0
  try { $qty = ($read3.text | ConvertFrom-Json).quantity } catch {}
  Add-Finding 'buyer_inflate_qty_prepay' ($qty -le 1) "qty after inflate=$qty (stock=3) HTTP $($upQty.status) $($read3.text.Substring(0,[Math]::Min(100,$read3.text.Length)))"

  $sellerPago = Invoke-Api PATCH "$Rest/orders?id=eq.$orderId" (AuthH $sellerJwt) @{ status = 'pago' }
  $read4 = Invoke-Api GET "$Rest/orders?select=status,amount_paid_cents,stock_units_applied&id=eq.$orderId" (AuthH $sellerJwt)
  $st4 = ''
  try { $st4 = ($read4.text | ConvertFrom-Json).status } catch {}
  Add-Finding 'seller_mark_pago_no_stripe' ($st4 -ne 'pago') "seller PATCH pago -> $st4 $($read4.text.Substring(0,[Math]::Min(140,$read4.text.Length))) HTTP $($sellerPago.status)"

  $rel = Invoke-Api POST "$Rest/rpc/batata_release_seller_wallet_for_order" (AuthH $buyerJwt) @{ p_order_id = $orderId }
  Add-Finding 'jwt_release_unpaid' ($true) "release HTTP $($rel.status) $($rel.text.Substring(0,[Math]::Min(160,$rel.text.Length)))"

  # Checkout underpay + swapped ids
  $cpiUnder = Invoke-Api POST "$Fn/create-payment-intent" (AuthH $buyerJwt) @{
    amount = 50
    currency = 'eur'
    product_id = $productId
    buyer_id = $BuyerId
    seller_id = $SellerId
    order_id = $orderId
    quantity = 1
    item_price = 50
    shipping = 0
    protection_fee = 0
    shipping_method = 'hand'
  }
  $cpiTxt = $cpiUnder.text
  $serverAmt = $null
  try { $serverAmt = ($cpiTxt | ConvertFrom-Json).server_amount_cents } catch {}
  $underBlocked = ($cpiUnder.status -ge 400) -or ($serverAmt -ne 50)
  Add-Finding 'checkout_underpay_ignored' $underBlocked "HTTP $($cpiUnder.status) server_amount_cents=$serverAmt body=$($cpiTxt.Substring(0,[Math]::Min(180,$cpiTxt.Length)))"

  $cpiShip0 = Invoke-Api POST "$Fn/create-payment-intent" (AuthH $buyerJwt) @{
    amount = 1
    currency = 'eur'
    product_id = $productId
    buyer_id = $BuyerId
    seller_id = $SellerId
    order_id = $orderId
    shipping = 0
    shipping_method = 'carrier'
  }
  $shipAmt = $null
  try { $shipAmt = ($cpiShip0.text | ConvertFrom-Json).server_amount_cents } catch {}
  Add-Finding 'checkout_shipping_client_zero' (($null -ne $shipAmt -and $shipAmt -ge 350) -or $cpiShip0.status -ge 400) "HTTP $($cpiShip0.status) server=$shipAmt $($cpiShip0.text.Substring(0,[Math]::Min(140,$cpiShip0.text.Length)))"

  $cpiWrongBuyer = Invoke-Api POST "$Fn/create-payment-intent" (AuthH $sellerJwt) @{
    amount = 1200
    currency = 'eur'
    product_id = $productId
    buyer_id = $BuyerId
    seller_id = $SellerId
    order_id = $orderId
    shipping_method = 'hand'
  }
  Add-Finding 'checkout_seller_as_buyer' ($cpiWrongBuyer.status -ge 400) "HTTP $($cpiWrongBuyer.status) $($cpiWrongBuyer.text.Substring(0,[Math]::Min(140,$cpiWrongBuyer.text.Length)))"

  $refBuyer = Invoke-Api POST "$Fn/refund-order" (AuthH $buyerJwt) @{ order_id = $orderId }
  Add-Finding 'buyer_refund_edge' ($refBuyer.status -ge 400 -or ($refBuyer.text -match 'Sem permiss')) "HTTP $($refBuyer.status) $($refBuyer.text.Substring(0,[Math]::Min(140,$refBuyer.text.Length)))"

  $payOther = Invoke-Api POST "$Fn/create-connect-account" (AuthH $buyerJwt) @{ user_id = $SellerId; amount = 100; idempotency_key = "blind-$tag" }
  Add-Finding 'payout_other_user' ($payOther.status -ge 400) "HTTP $($payOther.status) $($payOther.text.Substring(0,[Math]::Min(140,$payOther.text.Length)))"
}

# Seller price hike then quote
if ($productId -and $orderId) {
  $null = Invoke-Api PATCH "$Rest/products?id=eq.$productId" (AuthH $sellerJwt) @{ price = 80.00 }
  $cpiHike = Invoke-Api POST "$Fn/create-payment-intent" (AuthH $buyerJwt) @{
    amount = 1200
    currency = 'eur'
    product_id = $productId
    buyer_id = $BuyerId
    seller_id = $SellerId
    order_id = $orderId
    shipping_method = 'hand'
  }
  $hikeAmt = $null
  try { $hikeAmt = ($cpiHike.text | ConvertFrom-Json).server_amount_cents } catch {}
  $hikeUsesCatalog = ($hikeAmt -ge 8000)
  Add-Finding 'seller_price_hike_affects_checkout' (-not $hikeUsesCatalog) "HTTP $($cpiHike.status) server_amount_cents=$hikeAmt (12EUR order, catalog now 80EUR) $($cpiHike.text.Substring(0,[Math]::Min(120,$cpiHike.text.Length)))"
  $null = Invoke-Api PATCH "$Rest/products?id=eq.$productId" (AuthH $sellerJwt) @{ price = 12.00 }
}

# Bundle overcharge: two products, bag checkout vs sum of catalog
$prod2Id = $null
if ($productId) {
  $p2 = Invoke-Api POST "$Rest/products" (AuthH $sellerJwt) @{
    seller_id = $SellerId; title = "${tag}_B"; price = 10.00; quantity = 2
    list_on_marketplace = $false; available_for_live = $false; image_urls = @(); description = 'disposable B'
  }
  try { $prod2Id = ($p2.text | ConvertFrom-Json).id } catch {}
}
$oidA = $null; $oidB = $null
if ($productId -and $prod2Id) {
  $oa = Invoke-Api POST "$Rest/orders" (AuthH $buyerJwt) @{
    product_id = $productId; buyer_id = $BuyerId; seller_id = $SellerId
    price_total = 9.00; quantity = 1; status = 'reservado'; payment_method = 'Pagamento na app'; shipping_method = 'hand'
  }
  $ob = Invoke-Api POST "$Rest/orders" (AuthH $buyerJwt) @{
    product_id = $prod2Id; buyer_id = $BuyerId; seller_id = $SellerId
    price_total = 9.00; quantity = 1; status = 'reservado'; payment_method = 'Pagamento na app'; shipping_method = 'hand'
  }
  try { $oidA = ($oa.text | ConvertFrom-Json).id } catch {}
  try { $oidB = ($ob.text | ConvertFrom-Json).id } catch {}
  if ($oidA -and $oidB) {
    $bag = Invoke-Api POST "$Fn/create-payment-intent" (AuthH $buyerJwt) @{
      amount = 1800
      currency = 'eur'
      product_id = $productId
      buyer_id = $BuyerId
      seller_id = $SellerId
      order_id = $oidA
      shipping_method = 'hand'
      bag_checkout = $true
      bag_lines = @(
        @{ order_id = $oidA; product_id = $productId; line_total_cents = 900 }
        @{ order_id = $oidB; product_id = $prod2Id; line_total_cents = 900 }
      )
    }
    $bagAmt = $null
    try { $bagAmt = ($bag.text | ConvertFrom-Json).server_amount_cents } catch {}
    # catalog 12+10=22 EUR items + protection on 22 (hand 0). Discounted client 18 EUR ignored.
    $over = ($null -ne $bagAmt -and $bagAmt -gt 2000)
    Add-Finding 'bundle_discount_ignored_by_stripe' (-not $over) "HTTP $($bag.status) server=$bagAmt (client claimed 1800c; catalog 12+10) $($bag.text.Substring(0,[Math]::Min(140,$bag.text.Length)))"
  }
}

# Stranger cross
if ($strangerJwt -and $orderId) {
  $sOrd = Invoke-Api GET "$Rest/orders?select=id,price_total&id=eq.$orderId" (AuthH $strangerJwt)
  $saw = $sOrd.text -match $orderId
  Add-Finding 'stranger_read_order' (-not $saw) "HTTP $($sOrd.status) $($sOrd.text.Substring(0,[Math]::Min(80,$sOrd.text.Length)))"
}

# Storage list private
$stPriv = Invoke-Api GET "$Base/storage/v1/object/list/fleaber_private" (AuthH $buyerJwt)
Add-Finding 'storage_private_list' ($stPriv.status -ge 400 -or $stPriv.text -eq '[]' -or $stPriv.text.Length -lt 5) "HTTP $($stPriv.status) len=$($stPriv.text.Length)"

$fase2 = Invoke-Api POST "$Fn/create-payment-intent?fase2_e2e_settle=1" (AuthH $buyerJwt) @{ order_id = 'x'; payment_intent_id = 'pi_x' }
Add-Finding 'fase2_e2e_jwt' ($fase2.status -ge 400) "HTTP $($fase2.status) $($fase2.text.Substring(0,[Math]::Min(120,$fase2.text.Length)))"

$oversell = Invoke-Api POST "$Fn/sec-fase2-e2e-oversell" (AuthH $buyerJwt) @{ probe = '1' }
Add-Finding 'e2e_oversell_jwt' ($oversell.status -ge 400) "HTTP $($oversell.status) $($oversell.text.Substring(0,[Math]::Min(120,$oversell.text.Length)))"

$psClaim = Invoke-Api POST "$Fn/ps-pairing-claim" @{ apikey = $Anon } @{ code = '000000'; device_id = 'blind-audit' }
Add-Finding 'ps_claim_bad_code' ($psClaim.status -ge 400 -or ($psClaim.text -match 'invalid')) "HTTP $($psClaim.status) $($psClaim.text.Substring(0,[Math]::Min(120,$psClaim.text.Length)))"

$ocr = Invoke-Api POST "$Fn/ingest-ocr-reservation" @{ apikey = $Anon } @{ live_id = '00000000-0000-0000-0000-000000000001'; ocr_line_hash = 'abcdefghij'; detected_at = [DateTime]::UtcNow.ToString('o'); ref_number = 1 }
Add-Finding 'ocr_no_token' ($ocr.status -ge 400) "HTTP $($ocr.status) $($ocr.text.Substring(0,[Math]::Min(120,$ocr.text.Length)))"

$mux = Invoke-Api POST "$Fn/create-mux-live" (AuthH $buyerJwt) @{ title = 'Blind audit live title xx' }
Add-Finding 'buyer_create_mux' ($mux.status -ge 400) "HTTP $($mux.status) $($mux.text.Substring(0,[Math]::Min(140,$mux.text.Length)))"

$del = Invoke-Api POST "$Fn/delete-test-account" (AuthH $buyerJwt) @{ confirm = 'APAGAR TUDO' }
Add-Finding 'nuke_non_allowlist' ($del.status -ge 400) "HTTP $($del.status) $($del.text.Substring(0,[Math]::Min(140,$del.text.Length)))"

$emailEnum = Invoke-Api POST "$Rest/rpc/batata_find_user_id_by_email" (AuthH $buyerJwt) @{ p_email = $SellerEmail }
Add-Finding 'email_enum_rpc' ($emailEnum.status -ge 400 -or ($emailEnum.text -eq 'null')) "HTTP $($emailEnum.status) $($emailEnum.text.Substring(0,[Math]::Min(80,$emailEnum.text.Length)))"

# Cleanup disposable
if ($orderId) { $null = Invoke-Api PATCH "$Rest/orders?id=eq.$orderId" (AuthH $buyerJwt) @{ status = 'cancelado' } }
if ($oidA) { $null = Invoke-Api PATCH "$Rest/orders?id=eq.$oidA" (AuthH $buyerJwt) @{ status = 'cancelado' } }
if ($oidB) { $null = Invoke-Api PATCH "$Rest/orders?id=eq.$oidB" (AuthH $buyerJwt) @{ status = 'cancelado' } }
if ($productId) { $null = Invoke-Api PATCH "$Rest/products?id=eq.$productId" (AuthH $sellerJwt) @{ list_on_marketplace = $false; quantity = 0; is_sold = $true } }
if ($prod2Id) { $null = Invoke-Api PATCH "$Rest/products?id=eq.$prod2Id" (AuthH $sellerJwt) @{ list_on_marketplace = $false; quantity = 0; is_sold = $true } }

$reportPath = Join-Path $PSScriptRoot 'reports\_blind_audit_probes_20260827.json'
$Out | ConvertTo-Json -Depth 4 | Set-Content -Path $reportPath -Encoding UTF8
Write-Host "Wrote $reportPath"
$Out | Format-Table -AutoSize
