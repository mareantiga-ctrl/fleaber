# Follow-up probes + restore hijacked chat. JWT attacker. service_role restore only.
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
function Add-Result([string]$id, $obj) { $script:out[$id] = $obj; Write-Host ("{0}: {1}" -f $id, (($obj | ConvertTo-Json -Compress -Depth 6).Substring(0, [Math]::Min(240, (($obj | ConvertTo-Json -Compress -Depth 6).Length))))) }

function Invoke-Api {
  param([string]$Method, [string]$Url, [hashtable]$Headers, $Body)
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
function SignIn([string]$email, [string]$pass) {
  $r = Invoke-Api POST "$Base/auth/v1/token?grant_type=password" @{ apikey = $Anon } @{ email = $email; password = $pass }
  if (-not $r.ok) { throw "login failed $email $($r.status) $($r.text)" }
  return $r.body.access_token
}

$buyerJwt = SignIn $BuyerEmail $BuyerPass
$sellerJwt = SignIn $SellerEmail $SellerPass
$BH = AuthHeaders $buyerJwt
$SH = AuthHeaders $sellerJwt
$AH = @{ apikey = $Anon; Authorization = "Bearer $Anon" }
$svcH = @{ apikey = $Svc; Authorization = "Bearer $Svc"; Prefer = 'return=representation' }

# RESTORE hijacked chat immediately
$chatId = '401b48f1-7d00-4293-ab98-55fdf2135cf7'
$restore = Invoke-Api PATCH "$Base/rest/v1/chats?id=eq.$chatId" $svcH @{ user_a = $BuyerId; user_b = $SellerId }
Add-Result 'restore_chat' $restore
$chatNow = Invoke-Api GET "$Base/rest/v1/chats?select=id,user_a,user_b&id=eq.$chatId" $svcH
Add-Result 'chat_after_restore' $chatNow

# Seller wallet before
$swBefore = Invoke-Api GET "$Base/rest/v1/wallets?select=id,balance&id=eq.$SellerId" $SH
Add-Result 'seller_wallet_before' $swBefore
$bwBefore = Invoke-Api GET "$Base/rest/v1/wallets?select=id,balance&id=eq.$BuyerId" $BH
Add-Result 'buyer_wallet_before' $bwBefore

# Cross-user debit (the critical one)
$oid = [guid]::NewGuid().ToString()
Add-Result 'buyer_debit_seller_wallet' (Invoke-Api POST "$Base/rest/v1/rpc/batata_debit_wallet_once" $BH @{
  p_wallet_id = $SellerId
  p_order_id = $oid
  p_amount = 5
  p_description = 'AUDITCEGA27 cross debit'
})
$swAfter = Invoke-Api GET "$Base/rest/v1/wallets?select=id,balance&id=eq.$SellerId" $SH
Add-Result 'seller_wallet_after_cross_debit' $swAfter

# Debit own again with different description (append-only uniqueness)
Add-Result 'buyer_debit_self_again' (Invoke-Api POST "$Base/rest/v1/rpc/batata_debit_wallet_once" $BH @{
  p_wallet_id = $BuyerId
  p_order_id = [guid]::NewGuid().ToString()
  p_amount = 0.01
  p_description = 'AUDITCEGA27 self2'
})

# Credit still denied?
Add-Result 'buyer_credit_seller' (Invoke-Api POST "$Base/rest/v1/rpc/batata_credit_wallet_once" $BH @{
  p_wallet_id = $SellerId
  p_order_id = [guid]::NewGuid().ToString()
  p_amount = 5
  p_type = 'venda'
  p_description = 'AUDITCEGA27'
})

# clawback JWT
Add-Result 'buyer_clawback' (Invoke-Api POST "$Base/rest/v1/rpc/batata_clawback_seller_wallet_for_order" $BH @{ p_order_id = $oid })

# Authenticated reviews dump
Add-Result 'buyer_reviews_dump' (Invoke-Api GET "$Base/rest/v1/reviews?select=id,buyer_id,order_id,comment,stars&limit=8" $BH)
Add-Result 'anon_reviews2' (Invoke-Api GET "$Base/rest/v1/reviews?select=id,buyer_id,order_id,comment&limit=8" $AH)

# Lives column select without keys
Add-Result 'buyer_lives_public_cols' (Invoke-Api GET "$Base/rest/v1/lives?select=id,status,is_active,mux_playback_id&limit=3" $BH)
Add-Result 'seller_lives_own_nokey' (Invoke-Api GET "$Base/rest/v1/lives?select=id,status,mux_playback_id&limit=3" $SH)

# Raffle RPCs with likely signatures
Add-Result 'prize_2arg' (Invoke-Api POST "$Base/rest/v1/rpc/batata_create_raffle_prize_order" $BH @{ p_raffle_id = [guid]::NewGuid().ToString(); p_user_id = $BuyerId })
Add-Result 'draw_2arg' (Invoke-Api POST "$Base/rest/v1/rpc/batata_draw_live_raffle_winners" $BH @{ p_raffle_id = [guid]::NewGuid().ToString() })

# Chat hijack retry after restore
Add-Result 'chat_hijack_retry' (Invoke-Api PATCH "$Base/rest/v1/chats?id=eq.$chatId" $BH @{ user_b = ([guid]::NewGuid().ToString()) })
$chat2 = Invoke-Api GET "$Base/rest/v1/chats?select=id,user_a,user_b&id=eq.$chatId" $BH
Add-Result 'chat_after_hijack_retry' $chat2

# Restore again if hijack still works
$nowB = $null
if ($chat2.ok -and $chat2.body) {
  $row = if ($chat2.body -is [array]) { $chat2.body[0] } else { $chat2.body }
  $nowB = $row.user_b
}
if ($nowB -ne $SellerId) {
  $r2 = Invoke-Api PATCH "$Base/rest/v1/chats?id=eq.$chatId" $svcH @{ user_a = $BuyerId; user_b = $SellerId }
  Add-Result 'restore_chat_again' $r2
}

# Products: buyer update someone else qty
Add-Result 'buyer_patch_foreign_product' (Invoke-Api PATCH "$Base/rest/v1/products?seller_id=eq.$SellerId&select=id" $BH @{ quantity = 0 })

# Seller payout RPC
Add-Result 'seller_payout_debit_jwt' (Invoke-Api POST "$Base/rest/v1/rpc/batata_wallet_payout_debit" $SH @{
  p_user_id = $SellerId; p_amount_cents = 100; p_idempotency_key = 'auditcega27yyyyyyyy'
})

# If cross-debit succeeded, restore seller balance via service_role credit? We must NOT mint extra.
# Observe tx
Add-Result 'seller_tx_recent' (Invoke-Api GET "$Base/rest/v1/wallet_transactions?select=id,amount,type,description,order_id,created_at&wallet_id=eq.$SellerId&order=created_at.desc&limit=5" $SH)
Add-Result 'buyer_tx_recent' (Invoke-Api GET "$Base/rest/v1/wallet_transactions?select=id,amount,type,description,order_id,created_at&wallet_id=eq.$BuyerId&order=created_at.desc&limit=5" $BH)

# Restore seller funds if drained (service_role UPDATE balance + delete probe tx)
$swFinal = Invoke-Api GET "$Base/rest/v1/wallets?select=id,balance&id=eq.$SellerId" $SH
$sellerBal = 0
if ($swFinal.ok -and $swFinal.body) {
  $sb = if ($swFinal.body -is [array]) { $swFinal.body[0] } else { $swFinal.body }
  $sellerBal = [decimal]$sb.balance
}
$swBeforeBal = 0
if ($swBefore.ok -and $swBefore.body) {
  $sbb = if ($swBefore.body -is [array]) { $swBefore.body[0] } else { $swBefore.body }
  $swBeforeBal = [decimal]$sbb.balance
}
Add-Result 'seller_balance_delta' @{ before = $swBeforeBal; after = $sellerBal }

if ($sellerBal -lt $swBeforeBal) {
  $diff = $swBeforeBal - $sellerBal
  Add-Result 'restore_seller_balance' (Invoke-Api PATCH "$Base/rest/v1/wallets?id=eq.$SellerId" $svcH @{ balance = $swBeforeBal })
  Add-Result 'delete_probe_seller_tx' (Invoke-Api DELETE "$Base/rest/v1/wallet_transactions?wallet_id=eq.$SellerId&description=eq.AUDITCEGA27 cross debit" $svcH)
}

$bwNow = Invoke-Api GET "$Base/rest/v1/wallets?select=id,balance&id=eq.$BuyerId" $BH
Add-Result 'buyer_wallet_end' $bwNow
# Restore buyer 31.00 if we debited (was 31, then 30 after first probe, maybe 29.99)
$bb = 0
if ($bwNow.ok -and $bwNow.body) {
  $br = if ($bwNow.body -is [array]) { $bwNow.body[0] } else { $bwNow.body }
  $bb = [decimal]$br.balance
}
if ($bb -lt 31) {
  Add-Result 'restore_buyer_balance' (Invoke-Api PATCH "$Base/rest/v1/wallets?id=eq.$BuyerId" $svcH @{ balance = 31.00 })
  Add-Result 'delete_probe_buyer_tx' (Invoke-Api DELETE "$Base/rest/v1/wallet_transactions?wallet_id=eq.$BuyerId&description=like.AUDITCEGA27*" $svcH)
}

# Confirm remaining AUDITCEGA27 products/orders
Add-Result 'leftover_products' (Invoke-Api GET "$Base/rest/v1/products?select=id,title,quantity&title=eq.AUDITCEGA27 stock probe" $svcH)
Add-Result 'leftover_orders' (Invoke-Api GET "$Base/rest/v1/orders?select=id,status,product_id&price_total=eq.7.77&limit=10" $svcH)

$path = Join-Path $PSScriptRoot 'reports\_audit_cega_indep_20260827_followup.json'
[IO.File]::WriteAllText($path, ($out | ConvertTo-Json -Depth 10))
Write-Host "WROTE $path keys=$($out.Count)"
