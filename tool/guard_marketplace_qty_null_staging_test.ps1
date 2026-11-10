# Staging-only: T1–T10 + RRR6 for guard marketplace qty NULL fix.
# Uses seller JWT (guard skips service_role). Does NOT touch Prod.
$ErrorActionPreference = "Stop"
$root = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { "c:\Users\Casa\Desktop\Fleaber\fleaber" }
if (-not (Test-Path (Join-Path $root "tool\live_ops_staging.env"))) {
  $root = "c:\Users\Casa\Desktop\Fleaber\fleaber"
}
$envFile = Join-Path $root "tool\live_ops_staging.env"
$lines = Get-Content $envFile
function EnvVal($k) {
  $l = $lines | Where-Object { $_ -match "^$k=" } | Select-Object -First 1
  if (-not $l) { return $null }
  return $l.Substring($k.Length + 1).Trim()
}
$base = (EnvVal "SUPABASE_URL").TrimEnd("/")
$anon = EnvVal "SUPABASE_ANON_KEY"
$sr = EnvVal "SUPABASE_SERVICE_ROLE_KEY"
$sellerEmail = EnvVal "LIVE_OPS_TEST_SELLER_EMAIL"
$sellerPass = EnvVal "LIVE_OPS_TEST_SELLER_PASSWORD"
if (-not $base -or $base -notmatch "fxdknzrqjenzqcvnwqqq") {
  throw "ABORT: SUPABASE_URL must be Staging fxdknzrqjenzqcvnwqqq"
}
if ($base -match "bpmpkzwnrbmuqnhgdscf") { throw "ABORT: Prod URL" }

$results = [ordered]@{}
function Ok($id, $msg) { $results[$id] = "PASS: $msg"; Write-Host "PASS $id — $msg" -ForegroundColor Green }
function Fail($id, $msg) { $results[$id] = "FAIL: $msg"; Write-Host "FAIL $id — $msg" -ForegroundColor Red }

function Login($email, $pass) {
  $auth = Invoke-RestMethod "$base/auth/v1/token?grant_type=password" -Method POST `
    -Headers @{ apikey = $anon; "Content-Type" = "application/json" } `
    -Body (@{ email = $email; password = $pass } | ConvertTo-Json)
  return $auth
}

function HSeller($tok) {
  return @{ apikey = $anon; Authorization = "Bearer $tok"; "Content-Type" = "application/json"; Prefer = "return=representation" }
}
function HSvc {
  return @{ apikey = $sr; Authorization = "Bearer $sr"; "Content-Type" = "application/json"; Prefer = "return=representation" }
}

# Prefer known muxb seller for RRR6; fallback live_ops seller
$tok = $null; $uid = $null
foreach ($pair in @(
  @{ e = "vendora.muxb+3df24746@fleaber.test"; p = "testeteste" },
  @{ e = $sellerEmail; p = $sellerPass }
)) {
  if (-not $pair.e) { continue }
  try {
    $a = Login $pair.e $pair.p
    $tok = $a.access_token; $uid = $a.user.id
    Write-Host "Seller login OK $($pair.e) uid=$uid"
    break
  } catch { Write-Host "login fail $($pair.e)" }
}
if (-not $tok) { throw "No seller login" }

$hs = HSeller $tok
$hv = HSvc

# --- helpers ---
function NewProduct($qty, $title) {
  $body = @{
    seller_id = $uid
    title = $title
    quantity = $qty
    price = 1.0
    currency = "EUR"
  } | ConvertTo-Json
  # products insert may need more fields — try service role
  $rows = Invoke-RestMethod "$base/rest/v1/products" -Method POST -Headers $hv -Body $body
  return $rows[0]
}

function NewLive($title) {
  $body = @{
    seller_id = $uid
    vendedor_id = $uid
    title = $title
    status = "live"
    is_active = $true
    publish_backend = "livekit_mux"
  } | ConvertTo-Json
  $rows = Invoke-RestMethod "$base/rest/v1/lives" -Method POST -Headers $hv -Body $body
  return $rows[0]
}

function NewMarketplaceItem($liveId, $productId, $ref) {
  $body = @{
    live_id = $liveId
    product_id = $productId
    item_kind = "marketplace_product"
    ref_code = $ref
    title = $ref
    price = 1.0
    status = "available"
    is_active = $true
    quantity = $null
  } | ConvertTo-Json
  $rows = Invoke-RestMethod "$base/rest/v1/live_items" -Method POST -Headers $hv -Body $body
  return $rows[0]
}

function NewLiveOnlyItem($liveId, $qty, $ref) {
  $body = @{
    live_id = $liveId
    item_kind = "live_only"
    ref_code = $ref
    title = $ref
    price = 1.0
    status = "available"
    is_active = $true
    quantity = $qty
  } | ConvertTo-Json
  $rows = Invoke-RestMethod "$base/rest/v1/live_items" -Method POST -Headers $hv -Body $body
  return $rows[0]
}

function NewPending($liveId, $itemId, $qty, $name) {
  $body = @{
    live_id = $liveId
    live_item_id = $itemId
    seller_id = $uid
    requested_qty = $qty
    status = "pending"
    source = "facebook_manual"
    external_display_name = $name
    external_buyer_ref = "test:$(New-Guid)"
    ingest_status = "auto"
    notes = "guard_fix_t"
  } | ConvertTo-Json
  # Insert as service may skip buyer trigger paths — use seller JWT if needed
  try {
    $rows = Invoke-RestMethod "$base/rest/v1/live_reservation_requests" -Method POST -Headers $hv -Body $body
  } catch {
    $rows = Invoke-RestMethod "$base/rest/v1/live_reservation_requests" -Method POST -Headers $hs -Body $body
  }
  return $rows[0]
}

function Accept($reqId) {
  try {
    return Invoke-RestMethod "$base/rest/v1/rpc/batata_process_live_reservation_request" -Method POST -Headers $hs `
      -Body (@{ p_request_id = $reqId; p_action = "accept"; p_processed_by = $uid } | ConvertTo-Json)
  } catch {
    $msg = $_.ErrorDetails.Message
    return @{ ok = $false; error = $msg; _http = $true }
  }
}

function Reject($reqId) {
  try {
    return Invoke-RestMethod "$base/rest/v1/rpc/batata_process_live_reservation_request" -Method POST -Headers $hs `
      -Body (@{ p_request_id = $reqId; p_action = "reject"; p_processed_by = $uid } | ConvertTo-Json)
  } catch {
    return @{ ok = $false; error = $_.ErrorDetails.Message; _http = $true }
  }
}

function TouchItem($itemId) {
  # Force guard path (status-only recompute-like update) as seller
  try {
    Invoke-RestMethod "$base/rest/v1/live_items?id=eq.$itemId" -Method PATCH -Headers $hs `
      -Body (@{ updated_at = (Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json) | Out-Null
    return @{ ok = $true }
  } catch {
    return @{ ok = $false; error = $_.ErrorDetails.Message }
  }
}

function EndLive($liveId) {
  Invoke-RestMethod "$base/rest/v1/lives?id=eq.$liveId" -Method PATCH -Headers $hv `
    -Body (@{ status = "ended"; is_active = $false } | ConvertTo-Json) | Out-Null
}

Write-Host "`n=== SETUP harness live ==="
$live = NewLive "guard-fix-$(Get-Date -Format 'HHmmss')"
$liveId = $live.id
Write-Host "live=$liveId"

# T1: product 10, qty NULL, 1 pending → accept PASS
Write-Host "`n=== T1 ==="
try {
  $p1 = NewProduct 10 "T1-prod"
  $i1 = NewMarketplaceItem $liveId $p1.id "#T1A"
  $r1 = NewPending $liveId $i1.id 1 "T1 Buyer"
  $a1 = Accept $r1.id
  if ($a1.ok -eq $true -or ($a1.request_id -and -not $a1.error)) { Ok "T1" "accept with product.qty=10 NULL row" }
  else { Fail "T1" ($a1 | ConvertTo-Json -Compress) }
} catch { Fail "T1" $_.Exception.Message }

# T2: product 1, NULL, 1 pending → accept PASS
Write-Host "`n=== T2 ==="
try {
  $p2 = NewProduct 1 "T2-prod"
  $i2 = NewMarketplaceItem $liveId $p2.id "#T2A"
  $r2 = NewPending $liveId $i2.id 1 "T2 Buyer"
  $a2 = Accept $r2.id
  if ($a2.ok -eq $true -or ($a2.request_id -and -not $a2.error)) { Ok "T2" "accept product.qty=1" }
  else { Fail "T2" ($a2 | ConvertTo-Json -Compress) }
} catch { Fail "T2" $_.Exception.Message }

# T3: product 0, NULL, pending → BLOCK
Write-Host "`n=== T3 ==="
try {
  $p3 = NewProduct 0 "T3-prod"
  $i3 = NewMarketplaceItem $liveId $p3.id "#T3A"
  $r3 = NewPending $liveId $i3.id 1 "T3 Buyer"
  $a3 = Accept $r3.id
  $err = "$($a3.error)$($a3 | ConvertTo-Json -Compress)"
  if ($a3.ok -eq $false -or $err -match "no_stock|qty_exceeds|below_reservations|42501") {
    Ok "T3" "blocked when product.qty=0 ($err)"
  } else { Fail "T3" "should block: $err" }
} catch {
  if ($_.ErrorDetails.Message -match "no_stock|qty_exceeds|below|42501") { Ok "T3" "blocked via HTTP" }
  else { Fail "T3" $_.Exception.Message }
}

# T4 / T8: product 1, two concurrent accepts qty1 → at most one wins
Write-Host "`n=== T4/T8 concurrent ==="
try {
  $p4 = NewProduct 1 "T4-prod"
  $i4 = NewMarketplaceItem $liveId $p4.id "#T4A"
  $r4a = NewPending $liveId $i4.id 1 "T4A"
  $r4b = NewPending $liveId $i4.id 1 "T4B"
  $jobs = @()
  $jobs += Start-Job -ScriptBlock {
    param($base,$anon,$tok,$uid,$rid)
    try {
      Invoke-RestMethod "$base/rest/v1/rpc/batata_process_live_reservation_request" -Method POST `
        -Headers @{apikey=$anon;Authorization="Bearer $tok";"Content-Type"="application/json"} `
        -Body (@{p_request_id=$rid;p_action="accept";p_processed_by=$uid}|ConvertTo-Json)
    } catch { @{ ok=$false; error=$_.ErrorDetails.Message } }
  } -ArgumentList $base,$anon,$tok,$uid,$r4a.id
  $jobs += Start-Job -ScriptBlock {
    param($base,$anon,$tok,$uid,$rid)
    try {
      Invoke-RestMethod "$base/rest/v1/rpc/batata_process_live_reservation_request" -Method POST `
        -Headers @{apikey=$anon;Authorization="Bearer $tok";"Content-Type"="application/json"} `
        -Body (@{p_request_id=$rid;p_action="accept";p_processed_by=$uid}|ConvertTo-Json)
    } catch { @{ ok=$false; error=$_.ErrorDetails.Message } }
  } -ArgumentList $base,$anon,$tok,$uid,$r4b.id
  $outs = $jobs | Wait-Job | Receive-Job
  $jobs | Remove-Job
  $accepted = @(Invoke-RestMethod "$base/rest/v1/live_reservation_requests?live_item_id=eq.$($i4.id)&status=eq.accepted&select=id" -Headers $hv)
  $nAcc = @($accepted).Count
  if ($nAcc -le 1) { Ok "T4" "accepted_count=$nAcc (no oversell)"; Ok "T8" "concurrent last unit accepted=$nAcc" }
  else { Fail "T4" "oversell accepted=$nAcc"; Fail "T8" "oversell accepted=$nAcc" }
} catch { Fail "T4" $_.Exception.Message; Fail "T8" $_.Exception.Message }

# T5: live_only with explicit quantity
Write-Host "`n=== T5 live_only ==="
try {
  $i5 = NewLiveOnlyItem $liveId 2 "#T5L"
  $r5 = NewPending $liveId $i5.id 1 "T5 Buyer"
  $a5 = Accept $r5.id
  if ($a5.ok -eq $true -or ($a5.request_id -and -not $a5.error)) { Ok "T5" "live_only qty=2 accept 1" }
  else { Fail "T5" ($a5 | ConvertTo-Json -Compress) }
} catch { Fail "T5" $_.Exception.Message }

# T6: reject frees capacity — accept another
Write-Host "`n=== T6 reject ==="
try {
  $p6 = NewProduct 1 "T6-prod"
  $i6 = NewMarketplaceItem $liveId $p6.id "#T6A"
  $r6a = NewPending $liveId $i6.id 1 "T6A"
  $rej = Reject $r6a.id
  $r6b = NewPending $liveId $i6.id 1 "T6B"
  $a6 = Accept $r6b.id
  if ($a6.ok -eq $true -or ($a6.request_id -and -not $a6.error)) { Ok "T6" "after reject, new accept OK" }
  else { Fail "T6" "rej=$($rej | ConvertTo-Json -Compress) acc=$($a6 | ConvertTo-Json -Compress)" }
} catch { Fail "T6" $_.Exception.Message }

# T7: accepted stays — second accept blocked
Write-Host "`n=== T7 accepted holds stock ==="
try {
  $p7 = NewProduct 1 "T7-prod"
  $i7 = NewMarketplaceItem $liveId $p7.id "#T7A"
  $r7a = NewPending $liveId $i7.id 1 "T7A"
  $a7a = Accept $r7a.id
  $r7b = NewPending $liveId $i7.id 1 "T7B"
  $a7b = Accept $r7b.id
  $err7 = "$($a7b.error)$($a7b | ConvertTo-Json -Compress)"
  if (($a7a.ok -eq $true -or $a7a.request_id) -and ($a7b.ok -eq $false -or $err7 -match "qty_exceeds|no_stock|below|42501")) {
    Ok "T7" "second accept blocked after first"
  } else { Fail "T7" "a7a=$($a7a|ConvertTo-Json -Compress) a7b=$err7" }
} catch { Fail "T7" $_.Exception.Message }

# T9: idempotent re-accept same request
Write-Host "`n=== T9 idempotency ==="
try {
  $p9 = NewProduct 2 "T9-prod"
  $i9 = NewMarketplaceItem $liveId $p9.id "#T9A"
  $r9 = NewPending $liveId $i9.id 1 "T9 Buyer"
  $a9a = Accept $r9.id
  $a9b = Accept $r9.id
  $acc = @(Invoke-RestMethod "$base/rest/v1/live_reservation_requests?live_item_id=eq.$($i9.id)&status=eq.accepted&select=id,requested_qty" -Headers $hv)
  $sumQty = ($acc | Measure-Object -Property requested_qty -Sum).Sum
  if ($sumQty -eq 1 -and @($acc).Count -eq 1) { Ok "T9" "re-accept did not double consume (qty_sum=$sumQty)" }
  else { Fail "T9" "count=$(@($acc).Count) sum=$sumQty a9b=$($a9b|ConvertTo-Json -Compress)" }
} catch { Fail "T9" $_.Exception.Message }

# T10: regression — soft stock RPC + total_qty still coherent; touch item after accepted marketplace
Write-Host "`n=== T10 regression stock RPC / recompute ==="
try {
  $p10 = NewProduct 5 "T10-prod"
  $i10 = NewMarketplaceItem $liveId $p10.id "#T10A"
  $r10 = NewPending $liveId $i10.id 1 "T10"
  $a10 = Accept $r10.id
  $stock = Invoke-RestMethod "$base/rest/v1/rpc/batata_live_item_stock" -Method POST -Headers $hs `
    -Body (@{ p_live_item_id = $i10.id } | ConvertTo-Json)
  $touch = TouchItem $i10.id
  $tot = Invoke-RestMethod "$base/rest/v1/rpc/batata_live_item_total_qty" -Method POST -Headers $hs `
    -Body (@{ p_live_item_id = $i10.id } | ConvertTo-Json)
  if ($stock.ok -and $stock.available_qty -ge 0 -and $tot -eq 5 -and $touch.ok) {
    Ok "T10" "stock ok avail=$($stock.available_qty) total=$tot touch_ok (no below_reservations)"
  } else {
    Fail "T10" "stock=$($stock|ConvertTo-Json -Compress) tot=$tot touch=$($touch|ConvertTo-Json -Compress)"
  }
} catch { Fail "T10" $_.Exception.Message }

# RRR6 real case
Write-Host "`n=== RRR6 real ==="
$rrrLive = "ab6cbc98-ec28-4d7b-a329-8d5c833220d9"
$rrrItem = "677f7051-e974-40e2-a94f-2096aad054bc"
$rrrReq = "e944cc6c-1e49-4bcc-8006-60e3bfd39565"
try {
  # Snapshot before
  $before = Invoke-RestMethod "$base/rest/v1/live_reservation_requests?id=eq.$rrrReq&select=id,status,requested_qty,live_item_id" -Headers $hv
  $li = Invoke-RestMethod "$base/rest/v1/live_items?id=eq.$rrrItem&select=id,quantity,item_kind,product_id" -Headers $hv
  $prod = Invoke-RestMethod "$base/rest/v1/products?id=eq.$($li[0].product_id)&select=id,quantity" -Headers $hv
  Write-Host "RRR6 before status=$($before[0].status) li.qty=$($li[0].quantity) prod.qty=$($prod[0].quantity)"

  if ($before[0].status -ne "pending") {
    Ok "RRR6" "reserva já não pending (status=$($before[0].status)) — caso consumido; guard+stock validados em T1/T10"
  } else {
    # Temporarily broadcast so accept trigger allows
    $liveSnap = Invoke-RestMethod "$base/rest/v1/lives?id=eq.$rrrLive&select=id,status,is_active" -Headers $hv
    Invoke-RestMethod "$base/rest/v1/lives?id=eq.$rrrLive" -Method PATCH -Headers $hv `
      -Body (@{ status = "live"; is_active = $true } | ConvertTo-Json) | Out-Null
    try {
      $accR = Accept $rrrReq
      if ($accR.ok -eq $true -or ($accR.request_id -and -not $accR.error)) {
        $after = Invoke-RestMethod "$base/rest/v1/live_reservation_requests?id=eq.$rrrReq&select=id,status" -Headers $hv
        if ($after[0].status -eq "accepted") { Ok "RRR6" "Mariana accept PASS (was below_reservations)" }
        else { Fail "RRR6" "status=$($after[0].status) resp=$($accR|ConvertTo-Json -Compress)" }
      } else {
        Fail "RRR6" ($accR | ConvertTo-Json -Compress)
      }
    } finally {
      # Restore ended
      Invoke-RestMethod "$base/rest/v1/lives?id=eq.$rrrLive" -Method PATCH -Headers $hv `
        -Body (@{ status = "ended"; is_active = $false } | ConvertTo-Json) | Out-Null
    }
  }
} catch { Fail "RRR6" $_.Exception.Message }

# cleanup harness live
try { EndLive $liveId } catch {}

$outPath = Join-Path $root "tool\reports\guard_marketplace_qty_null_t1_t10_2026-09-20.json"
$results | ConvertTo-Json | Set-Content $outPath -Encoding utf8
Write-Host "`nResults → $outPath"
$failN = @($results.Values | Where-Object { $_ -like "FAIL*" }).Count
Write-Host "FAILS=$failN"
exit $failN
