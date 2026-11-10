# Targeted probes: cross-product stock, chat party, devolvida mint.
$ErrorActionPreference = 'Stop'
Get-Content (Join-Path $PSScriptRoot 'live_ops_staging.env') | ForEach-Object {
  $line = $_.Trim(); if ($line -eq '' -or $line.StartsWith('#')) { return }
  $eq = $line.IndexOf('='); if ($eq -lt 1) { return }
  Set-Item -Path ("Env:" + $line.Substring(0,$eq).Trim()) -Value $line.Substring($eq+1).Trim()
}
$Base = ($env:SUPABASE_URL -replace '/rest/v1/?$','')
$Anon = $env:SUPABASE_ANON_KEY
$Rest = "$Base/rest/v1"
$BuyerId = $env:LIVE_OPS_TEST_BUYER_ID
$SellerId = $env:LIVE_OPS_TEST_SELLER_ID
function Invoke-Api($Method,$Url,$Headers,$Body) {
  $h = @{ apikey = $Anon; Accept = 'application/json' }
  if ($Headers) { $Headers.GetEnumerator() | ForEach-Object { $h[$_.Key] = $_.Value } }
  $p = @{ Method=$Method; Uri=$Url; Headers=$h; TimeoutSec=40 }
  if ($null -ne $Body) { $p.ContentType='application/json'; $p.Body = ($Body | ConvertTo-Json -Depth 8 -Compress) }
  try { $r = Invoke-WebRequest @p; return @{ status=[int]$r.StatusCode; text=$r.Content } }
  catch { $resp=$_.Exception.Response; if($resp){ $rd=New-Object IO.StreamReader($resp.GetResponseStream()); return @{ status=[int]$resp.StatusCode; text=$rd.ReadToEnd() } }; return @{ status=0; text=$_.Exception.Message } }
}
function Sign-In($e,$pw) {
  $r = Invoke-Api POST "$Base/auth/v1/token?grant_type=password" @{ apikey=$Anon } @{ email=$e; password=$pw }
  if ($r.status -ne 200) { throw $r.text }
  return ($r.text | ConvertFrom-Json).access_token
}
function AH($jwt){ @{ Authorization="Bearer $jwt"; apikey=$Anon; Prefer='return=representation' } }

$b = Sign-In $env:LIVE_OPS_TEST_BUYER_EMAIL $env:LIVE_OPS_TEST_BUYER_PASSWORD
$s = Sign-In $env:LIVE_OPS_TEST_SELLER_EMAIL $env:LIVE_OPS_TEST_SELLER_PASSWORD

# Seller product qty
$prod = Invoke-Api GET "$Rest/products?select=id,quantity,seller_id,title&seller_id=eq.$SellerId&title=like.BLIND2_*&limit=1" (AH $s)
Write-Host "seller products leftover: $($prod.text)"
$pNew = Invoke-Api POST "$Rest/products" (AH $s) @{
  seller_id=$SellerId; title="BLIND3_$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; price=5; quantity=4
  list_on_marketplace=$false; available_for_live=$false; image_urls=@(); description='probe3'
}
$productId = ($pNew.text | ConvertFrom-Json).id
Write-Host "product=$productId qty=4"

# Attack: buyer is seller_id AND buyer_id, product belongs to real seller
$cross = Invoke-Api POST "$Rest/orders" (AH $b) @{
  product_id=$productId; buyer_id=$BuyerId; seller_id=$BuyerId; price_total=5; quantity=2
  status='reserva_pendente'; payment_method='MB WAY'; shipping_method='hand'
}
Write-Host "CROSS_INSERT HTTP $($cross.status) $($cross.text.Substring(0,[Math]::Min(220,$cross.text.Length)))"

# Chat hijack
$chats = Invoke-Api GET "$Rest/chats?select=id,user_a,user_b&or=(user_a.eq.$BuyerId,user_b.eq.$BuyerId)&limit=3" (AH $b)
Write-Host "CHATS $($chats.text.Substring(0,[Math]::Min(250,$chats.text.Length)))"
$chatId = $null
try {
  $arr = $chats.text | ConvertFrom-Json
  if ($arr -is [array] -and $arr.Count -gt 0) { $chatId = $arr[0].id } elseif ($arr.id) { $chatId = $arr.id }
} catch {}
if ($chatId) {
  $origA = $null; $origB = $null
  try {
    $crow = ($chats.text | ConvertFrom-Json)
    if ($crow -is [array]) { $origA = $crow[0].user_a; $origB = $crow[0].user_b } else { $origA = $crow.user_a; $origB = $crow.user_b }
  } catch {}
  $fake = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
  $patch = Invoke-Api PATCH "$Rest/chats?id=eq.$chatId" (AH $b) @{ user_b = $fake }
  Write-Host "CHAT_PATCH HTTP $($patch.status) $($patch.text.Substring(0,[Math]::Min(200,$patch.text.Length)))"
  $after = Invoke-Api GET "$Rest/chats?select=id,user_a,user_b&id=eq.$chatId" (AH $b)
  Write-Host "CHAT_AFTER $($after.text.Substring(0,[Math]::Min(180,$after.text.Length)))"
  if ($origA -and $origB) {
    $null = Invoke-Api PATCH "$Rest/chats?id=eq.$chatId" (AH $b) @{ user_a = $origA; user_b = $origB }
    Write-Host "CHAT_REVERT attempted to $origA / $origB"
  }
}

# devolvida from pago (own order)
$own = Invoke-Api POST "$Rest/orders" (AH $b) @{
  product_id=$productId; buyer_id=$BuyerId; seller_id=$SellerId; price_total=50; quantity=1
  status='reserva_pendente'; payment_method='Pagamento na app'; shipping_method='hand'
}
$oid = $null; try { $oid = ($own.text | ConvertFrom-Json).id } catch {}
Write-Host "OWN_ORDER $oid"
if ($oid) {
  $pago = Invoke-Api PATCH "$Rest/orders?id=eq.$oid" (AH $s) @{ status='pago' }
  Write-Host "SELLER_PAGO $($pago.text.Substring(0,[Math]::Min(120,$pago.text.Length)))"
  $w0 = Invoke-Api GET "$Rest/wallets?select=balance&id=eq.$BuyerId" (AH $b)
  Write-Host "WALLET_BEFORE $($w0.text)"
  $dev = Invoke-Api PATCH "$Rest/orders?id=eq.$oid" (AH $s) @{ status='devolvida' }
  Write-Host "SELLER_DEVOLVIDA HTTP $($dev.status) $($dev.text.Substring(0,[Math]::Min(160,$dev.text.Length)))"
  $st = Invoke-Api GET "$Rest/orders?select=status,amount_paid_cents&id=eq.$oid" (AH $s)
  Write-Host "STATUS_AFTER $($st.text)"
  $w1 = Invoke-Api GET "$Rest/wallets?select=balance&id=eq.$BuyerId" (AH $b)
  Write-Host "WALLET_AFTER $($w1.text)"
  $null = Invoke-Api PATCH "$Rest/orders?id=eq.$oid" (AH $b) @{ status='cancelado' }
}
$null = Invoke-Api PATCH "$Rest/products?id=eq.$productId" (AH $s) @{ quantity=0; is_sold=$true; list_on_marketplace=$false }
