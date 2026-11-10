# Follow-up probes on unpaid orders (checkout quote, price hike, bag, profiles, qty).
$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot 'live_ops_staging.env'
Get-Content $envFile | ForEach-Object {
  $line = $_.Trim()
  if ($line -eq '' -or $line.StartsWith('#')) { return }
  $eq = $line.IndexOf('=')
  if ($eq -lt 1) { return }
  Set-Item -Path ("Env:" + $line.Substring(0, $eq).Trim()) -Value $line.Substring($eq + 1).Trim()
}
$Base = ($env:SUPABASE_URL -replace '/rest/v1/?$', '')
$Anon = $env:SUPABASE_ANON_KEY
$Rest = "$Base/rest/v1"
$Fn = "$Base/functions/v1"
$BuyerId = $env:LIVE_OPS_TEST_BUYER_ID
$SellerId = $env:LIVE_OPS_TEST_SELLER_ID
$Out = @()
function Add-Finding($id, $ok, $detail) {
  $d = ($detail -replace '\s+', ' ')
  $script:Out += [pscustomobject]@{ id = $id; ok = $ok; detail = $d.Substring(0, [Math]::Min(600, $d.Length)) }
  Write-Host ("[{0}] {1}  {2}" -f $(if ($ok) {'HOLD'} else {'OPEN'}), $id, $d.Substring(0, [Math]::Min(200, $d.Length)))
}
function Invoke-Api($Method, $Url, $Headers, $Body) {
  $h = @{ apikey = $Anon; Accept = 'application/json' }
  if ($Headers) { $Headers.GetEnumerator() | ForEach-Object { $h[$_.Key] = $_.Value } }
  $p = @{ Method = $Method; Uri = $Url; Headers = $h; TimeoutSec = 45 }
  if ($null -ne $Body) { $p.ContentType = 'application/json'; $p.Body = ($Body | ConvertTo-Json -Depth 12 -Compress) }
  try { $resp = Invoke-WebRequest @p; return @{ status = [int]$resp.StatusCode; text = $resp.Content } }
  catch {
    $r = $_.Exception.Response
    if ($r) { $reader = New-Object IO.StreamReader($r.GetResponseStream()); return @{ status = [int]$r.StatusCode; text = $reader.ReadToEnd() } }
    return @{ status = 0; text = $_.Exception.Message }
  }
}
function Sign-In($email, $pass) {
  $r = Invoke-Api POST "$Base/auth/v1/token?grant_type=password" @{ apikey = $Anon } @{ email = $email; password = $pass }
  if ($r.status -ne 200) { throw "login $($r.status) $($r.text)" }
  return ($r.text | ConvertFrom-Json).access_token
}
function AuthH($jwt) { @{ Authorization = "Bearer $jwt"; apikey = $Anon; Prefer = 'return=representation' } }

$buyerJwt = Sign-In $env:LIVE_OPS_TEST_BUYER_EMAIL $env:LIVE_OPS_TEST_BUYER_PASSWORD
$sellerJwt = Sign-In $env:LIVE_OPS_TEST_SELLER_EMAIL $env:LIVE_OPS_TEST_SELLER_PASSWORD
$tag = "BLIND2_$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"

$p1 = Invoke-Api POST "$Rest/products" (AuthH $sellerJwt) @{
  seller_id = $SellerId; title = $tag; price = 12.00; quantity = 5
  list_on_marketplace = $false; available_for_live = $false; image_urls = @(); description = 'audit2'
}
$productId = ($p1.text | ConvertFrom-Json).id
$p2 = Invoke-Api POST "$Rest/products" (AuthH $sellerJwt) @{
  seller_id = $SellerId; title = "${tag}_B"; price = 10.00; quantity = 5
  list_on_marketplace = $false; available_for_live = $false; image_urls = @(); description = 'audit2b'
}
$productB = ($p2.text | ConvertFrom-Json).id

$o1 = Invoke-Api POST "$Rest/orders" (AuthH $buyerJwt) @{
  product_id = $productId; buyer_id = $BuyerId; seller_id = $SellerId
  price_total = 12.00; quantity = 1; status = 'reservado'
  payment_method = 'Pagamento na app'; shipping_method = 'hand'
}
$orderId = ($o1.text | ConvertFrom-Json).id
Add-Finding 'order_unpaid' ($null -ne $orderId) "order=$orderId product=$productId"

# Underpay body
$cpi = Invoke-Api POST "$Fn/create-payment-intent" (AuthH $buyerJwt) @{
  amount = 50; currency = 'eur'; product_id = $productId; buyer_id = $BuyerId
  seller_id = $SellerId; order_id = $orderId; quantity = 1; item_price = 50
  shipping = 0; protection_fee = 0; shipping_method = 'hand'
}
$amt = $null; try { $amt = ($cpi.text | ConvertFrom-Json).server_amount_cents } catch {}
# 12 EUR + 0 ship + prot 0.65+5%*12 = 1.25 => 1325 cents approx
Add-Finding 'checkout_quote_ignores_client_amount' (($cpi.status -eq 200) -and ($amt -gt 1000) -and ($amt -ne 50)) "HTTP $($cpi.status) server=$amt (client 50) $($cpi.text.Substring(0,[Math]::Min(160,$cpi.text.Length)))"

# Carrier with client shipping 0
$cpiC = Invoke-Api POST "$Fn/create-payment-intent" (AuthH $buyerJwt) @{
  amount = 50; currency = 'eur'; product_id = $productId; buyer_id = $BuyerId
  seller_id = $SellerId; order_id = $orderId; shipping = 0; shipping_method = 'carrier'
}
$amtC = $null; try { $amtC = ($cpiC.text | ConvertFrom-Json).server_amount_cents } catch {}
Add-Finding 'checkout_carrier_ignores_shipping_0' (($amtC -ge 350) -or $cpiC.status -ge 400) "HTTP $($cpiC.status) server=$amtC $($cpiC.text.Substring(0,[Math]::Min(120,$cpiC.text.Length)))"

# Price hike
$null = Invoke-Api PATCH "$Rest/products?id=eq.$productId" (AuthH $sellerJwt) @{ price = 80.00 }
$cpiH = Invoke-Api POST "$Fn/create-payment-intent" (AuthH $buyerJwt) @{
  amount = 1200; currency = 'eur'; product_id = $productId; buyer_id = $BuyerId
  seller_id = $SellerId; order_id = $orderId; shipping_method = 'hand'
}
$amtH = $null; try { $amtH = ($cpiH.text | ConvertFrom-Json).server_amount_cents } catch {}
$hike = ($amtH -ge 8000)
Add-Finding 'catalog_price_hike_controls_stripe' (-not $hike) "HTTP $($cpiH.status) server=$amtH expected~12EUR frozen vs 80EUR catalog"
$null = Invoke-Api PATCH "$Rest/products?id=eq.$productId" (AuthH $sellerJwt) @{ price = 12.00 }

# Qty inflate then quote
$upQ = Invoke-Api PATCH "$Rest/orders?id=eq.$orderId" (AuthH $buyerJwt) @{ quantity = 4 }
$cpiQ = Invoke-Api POST "$Fn/create-payment-intent" (AuthH $buyerJwt) @{
  amount = 1200; currency = 'eur'; product_id = $productId; buyer_id = $BuyerId
  seller_id = $SellerId; order_id = $orderId; shipping_method = 'hand'
}
$amtQ = $null; try { $amtQ = ($cpiQ.text | ConvertFrom-Json).server_amount_cents } catch {}
$qtyNow = $null; try { $qtyNow = ($upQ.text | ConvertFrom-Json).quantity } catch {}
Add-Finding 'qty_inflate_increases_stripe_quote' ($amtQ -lt 4000) "qty_after_patch=$qtyNow HTTP $($cpiQ.status) server=$amtQ (1 unit was 12EUR; 4 units would be ~48EUR+fee)"

# Reset qty 1
$null = Invoke-Api PATCH "$Rest/orders?id=eq.$orderId" (AuthH $buyerJwt) @{ quantity = 1 }

# Bag discount ignored
$oa = Invoke-Api POST "$Rest/orders" (AuthH $buyerJwt) @{
  product_id = $productId; buyer_id = $BuyerId; seller_id = $SellerId
  price_total = 9.00; quantity = 1; status = 'reservado'; payment_method = 'Pagamento na app'; shipping_method = 'hand'
}
$ob = Invoke-Api POST "$Rest/orders" (AuthH $buyerJwt) @{
  product_id = $productB; buyer_id = $BuyerId; seller_id = $SellerId
  price_total = 9.00; quantity = 1; status = 'reservado'; payment_method = 'Pagamento na app'; shipping_method = 'hand'
}
$oidA = ($oa.text | ConvertFrom-Json).id
$oidB = ($ob.text | ConvertFrom-Json).id
$bag = Invoke-Api POST "$Fn/create-payment-intent" (AuthH $buyerJwt) @{
  amount = 1800; currency = 'eur'; product_id = $productId; buyer_id = $BuyerId
  seller_id = $SellerId; order_id = $oidA; shipping_method = 'hand'
  bag_checkout = $true
  bag_lines = @(
    @{ order_id = $oidA; product_id = $productId; line_total_cents = 900 }
    @{ order_id = $oidB; product_id = $productB; line_total_cents = 900 }
  )
}
$bagAmt = $null; try { $bagAmt = ($bag.text | ConvertFrom-Json).server_amount_cents } catch {}
# catalog 12+10=2200c + prot ~1.75EUR = ~2375c. Client 1800c discounted.
Add-Finding 'bag_uses_catalog_not_line_total' ($bagAmt -le 1900) "HTTP $($bag.status) server=$bagAmt client=1800 catalog=12+10 $($bag.text.Substring(0,[Math]::Min(140,$bag.text.Length)))"

# Seller insert forged buyer
$forged = Invoke-Api POST "$Rest/orders" (AuthH $sellerJwt) @{
  product_id = $productId; buyer_id = '00000000-0000-0000-0000-000000000099'; seller_id = $SellerId
  price_total = 12; quantity = 1; status = 'reservado'; payment_method = 'Pagamento na app'; shipping_method = 'hand'
}
Add-Finding 'seller_insert_forged_buyer' ($forged.status -ge 400) "HTTP $($forged.status) $($forged.text.Substring(0,[Math]::Min(160,$forged.text.Length)))"

# Profiles PII as authenticated
$prof = Invoke-Api GET "$Rest/profiles?select=id,email,phone,mb_way,iban,full_name&id=eq.$SellerId" (AuthH $buyerJwt)
Add-Finding 'auth_read_seller_payout_pii' ($prof.text -notmatch 'mb_way' -and $prof.text -notmatch 'iban') "HTTP $($prof.status) $($prof.text.Substring(0,[Math]::Min(200,$prof.text.Length)))"

$profSelf = Invoke-Api GET "$Rest/profiles?select=id,mb_way,iban&id=eq.$BuyerId" (AuthH $buyerJwt)
Add-Finding 'auth_read_own_payout' ($true) "own $($profSelf.text.Substring(0,[Math]::Min(120,$profSelf.text.Length)))"

# RPC payout details
$payDet = Invoke-Api POST "$Rest/rpc/batata_seller_direct_payment_details" (AuthH $buyerJwt) @{ p_seller_id = $SellerId }
Add-Finding 'rpc_seller_payout_details' ($true) "HTTP $($payDet.status) $($payDet.text.Substring(0,[Math]::Min(160,$payDet.text.Length)))"

# GET settle unauth
$settle = Invoke-Api GET "$Fn/create-payment-intent?checkout_return=success&session_id=cs_test_invalid" @{ apikey = $Anon } $null
Add-Finding 'get_settle_unauth' ($true) "HTTP $($settle.status) $($settle.text.Substring(0,[Math]::Min(120,$settle.text.Length)))"

# Seller-only MB WAY pago vs stripe method: new unpaid, seller pago (confirm intended?)
$oMb = Invoke-Api POST "$Rest/orders" (AuthH $buyerJwt) @{
  product_id = $productB; buyer_id = $BuyerId; seller_id = $SellerId
  price_total = 10; quantity = 1; status = 'aguarda_confirmacao'
  payment_method = 'MB WAY'; shipping_method = 'hand'
}
$oidMb = ($oMb.text | ConvertFrom-Json).id
$mbPago = Invoke-Api PATCH "$Rest/orders?id=eq.$oidMb" (AuthH $sellerJwt) @{ status = 'pago' }
$mbSt = ''; try { $mbSt = ($mbPago.text | ConvertFrom-Json).status } catch {}
Add-Finding 'seller_mbway_pago_allowed' ($mbSt -eq 'pago') "MB WAY seller pago status=$mbSt (expected allowed for direct pay)"

# Wallet after fake concluido on unpaid stripe-method order (the first one still reservado)
$null = Invoke-Api PATCH "$Rest/orders?id=eq.$orderId" (AuthH $sellerJwt) @{ status = 'enviado' }
$null = Invoke-Api PATCH "$Rest/orders?id=eq.$orderId" (AuthH $buyerJwt) @{ status = 'concluido' }
$stFin = Invoke-Api GET "$Rest/orders?select=status,amount_paid_cents,wallet_release_processed_at&id=eq.$orderId" (AuthH $buyerJwt)
$rel2 = Invoke-Api POST "$Rest/rpc/batata_release_seller_wallet_for_order" (AuthH $buyerJwt) @{ p_order_id = $orderId }
$w = Invoke-Api GET "$Rest/wallets?select=id,balance&id=eq.$SellerId" (AuthH $sellerJwt)
Add-Finding 'fake_complete_no_wallet_mint' ($true) "order=$($stFin.text.Substring(0,[Math]::Min(140,$stFin.text.Length))) release=$($rel2.text.Substring(0,[Math]::Min(80,$rel2.text.Length))) wallet=$($w.text.Substring(0,[Math]::Min(80,$w.text.Length)))"

# Email enum 2nd call
$email2 = Invoke-Api POST "$Rest/rpc/batata_find_user_id_by_email" (AuthH $buyerJwt) @{ p_email = 'nobody-xyz@fleaber.test' }
Add-Finding 'email_enum_unknown' ($true) "HTTP $($email2.status) $($email2.text.Substring(0,[Math]::Min(80,$email2.text.Length)))"

# Cleanup
foreach ($oid in @($orderId, $oidA, $oidB, $oidMb)) {
  if ($oid) { $null = Invoke-Api PATCH "$Rest/orders?id=eq.$oid" (AuthH $buyerJwt) @{ status = 'cancelado' } }
}
foreach ($pid in @($productId, $productB)) {
  $null = Invoke-Api PATCH "$Rest/products?id=eq.$pid" (AuthH $sellerJwt) @{ quantity = 0; is_sold = $true; list_on_marketplace = $false }
}

$path = Join-Path $PSScriptRoot 'reports\_blind_audit_probes_20260827_b.json'
$Out | ConvertTo-Json -Depth 4 | Set-Content $path -Encoding UTF8
Write-Host "Wrote $path"
$Out | Format-Table -AutoSize
