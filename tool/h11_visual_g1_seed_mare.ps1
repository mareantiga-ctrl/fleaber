# H11 visual G1 — renomear produtos técnicos Mare + fotos + favoritos amostra.
# Sem cobranças/envios. Tag: H11_VISUAL_G1_20261027
$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$envFile = Join-Path $Root 'tool\live_ops_production.env'
$rep = Join-Path $Root 'tool\reports\fleahub_h11_visual_g1_2026-10-27'
New-Item -ItemType Directory -Path $rep -Force | Out-Null

function Get-EnvMap([string]$path) {
  $m = @{}
  foreach ($line in Get-Content $path) {
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith('#') -or -not $t.Contains('=')) { continue }
    $i = $t.IndexOf('=')
    $m[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
  }
  return $m
}

$envMap = Get-EnvMap $envFile
$url = $envMap['SUPABASE_URL']
$key = $envMap['SUPABASE_SERVICE_ROLE_KEY']
if (-not $url -or -not $key) { throw 'SUPABASE_* em falta' }

$MareId = '08c9dca8-3707-4ee5-9f43-b33293085d6a'
$BuyerId = $envMap['PROD_TEST_BUYER_H1132_ID']
$Tag = 'H11_VISUAL_G1_20261027'

$headers = @{
  apikey = $key
  Authorization = "Bearer $key"
  'Content-Type' = 'application/json'
  Prefer = 'return=representation'
}

function Invoke-Sb([string]$method, [string]$path, $body = $null) {
  $uri = "$url/rest/v1/$path"
  if ($null -eq $body) {
    return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers
  }
  $json = $body | ConvertTo-Json -Depth 8 -Compress
  return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -Body $json
}

# Fotos públicas Hub (já no CDN fleahub)
$photos = @(
  'https://fleaber.pt/fleahub/assets/assets/images/hub_landing/product1.jpg',
  'https://fleaber.pt/fleahub/assets/assets/images/hub_landing/product2.jpg',
  'https://fleaber.pt/fleahub/assets/assets/live_covers/fleaber_capa_10.webp',
  'https://fleaber.pt/fleahub/assets/assets/live_covers/fleaber_capa_20.webp',
  'https://fleaber.pt/fleahub/assets/assets/live_covers/fleaber_capa_30.webp',
  'https://fleaber.pt/fleahub/assets/assets/live_covers/fleaber_capa_40.webp'
)

$titles = @(
  'Casaco de ganga vintage azul',
  'Mala de cabedal camel',
  'Vestido floral leve',
  'Sapatilhas brancas clássicas',
  'Camisola de lã merino',
  'Calças chino bege'
)

Write-Host "Mare id=$MareId"
# Produtos Mare (seller) + títulos técnicos visíveis em encomendas Mare
$bySeller = @(Invoke-Sb GET ("products?seller_id=eq.$MareId&select=id,title,image_urls,price&order=created_at.desc&limit=40"))
$orderRows = @(Invoke-Sb GET ("orders?or=(seller_id.eq.$MareId,buyer_id.eq.$MareId)&select=product_id&order=created_at.desc&limit=40"))
$orderPids = @($orderRows | ForEach-Object { $_.product_id } | Where-Object { $_ } | Select-Object -Unique)
$fromOrders = @()
if ($orderPids.Count -gt 0) {
  $inList = ($orderPids | ForEach-Object { $_.ToString() }) -join ','
  $fromOrders = @(Invoke-Sb GET ("products?id=in.($inList)&select=id,title,image_urls,price"))
}
$products = @{}
foreach ($p in ($bySeller + $fromOrders)) { $products[[string]$p.id] = $p }
$updated = @()
$i = 0
foreach ($p in @($products.Values)) {
  $t = [string]$p.title
  $need = ($t -match 'H10_TESTE|E63 TEST|TEST PRODUCT|\[H10') -or ($i -lt 6)
  if (-not $need) { continue }
  $newTitle = $titles[$i % $titles.Count]
  $newPhoto = $photos[$i % $photos.Count]
  $patch = @{ title = $newTitle; image_urls = @($newPhoto) }
  try {
    Invoke-Sb PATCH ("products?id=eq.$($p.id)") $patch | Out-Null
    $updated += [pscustomobject]@{
      id = $p.id
      old_title = $t
      new_title = $newTitle
      image_urls = @($newPhoto)
    }
    Write-Host "OK product $($p.id) -> $newTitle"
  } catch {
    Write-Host "FAIL product $($p.id): $_"
  }
  $i++
  if ($i -ge 10) { break }
}

# Favoritos na conta Mare (e amostra H1132) nos produtos actualizados
$favAdded = @()
$favUsers = @($MareId)
if ($BuyerId) { $favUsers += $BuyerId }
foreach ($uid in $favUsers) {
  foreach ($u in $updated | Select-Object -First 5) {
    try {
      $body = @{ user_id = $uid; product_id = $u.id }
      $h2 = @{}
      foreach ($k in $headers.Keys) { $h2[$k] = $headers[$k] }
      $h2['Prefer'] = 'resolution=merge-duplicates,return=minimal'
      $uri = "$url/rest/v1/favorites?on_conflict=user_id,product_id"
      $json = ($body | ConvertTo-Json -Compress)
      Invoke-RestMethod -Method POST -Uri $uri -Headers $h2 -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) | Out-Null
      $favAdded += "$uid::$($u.id)"
      Write-Host "OK favorite $uid -> $($u.id)"
    } catch {
      Write-Host "fav skip $uid/$($u.id): $_"
    }
  }
}

# live_items titles for Mare lives (refs técnicas)
try {
  $lives = Invoke-Sb GET ("lives?seller_id=eq.$MareId&select=id&order=created_at.desc&limit=5")
  $liUpdated = @()
  foreach ($lv in @($lives)) {
    $items = Invoke-Sb GET ("live_items?live_id=eq.$($lv.id)&select=id,title,ref_code,photo_url&limit=20")
    $j = 0
    foreach ($it in @($items)) {
      $tt = [string]$it.title
      if ($tt -and $tt -notmatch '^(Ref|T\d+|REF)') { $j++; continue }
      $nt = $titles[$j % $titles.Count]
      $np = $photos[$j % $photos.Count]
      Invoke-Sb PATCH ("live_items?id=eq.$($it.id)") @{ title = $nt; photo_url = $np } | Out-Null
      $liUpdated += @{ id = $it.id; title = $nt }
      $j++
      if ($j -ge 6) { break }
    }
  }
} catch {
  Write-Host "live_items: $_"
  $liUpdated = @()
}

$inv = [ordered]@{
  tag = $Tag
  account_mare = 'mareantiga@gmail.com'
  mare_id = $MareId
  buyer_favorites = $BuyerId
  products_updated = $updated
  favorites_added = $favAdded
  live_items_updated = $liUpdated
  note = 'Limpeza: reverter titles/photos listados; apagar favorites H11_VISUAL_G1 se necessário. Não apagar conta Mare.'
}
$inv | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $rep 'INVENTARIO_DADOS_TESTE.json') -Encoding UTF8
@"
# Limpeza H11 Visual G1 ($Tag)

1. Restaurar `products` listados em INVENTARIO (title/photo_url) ou deixar se forem melhores.
2. Remover favorites do comprador H1132 para product_ids em favorites_added.
3. Reverter live_items titles/photos se necessário.
4. **Não** apagar `mareantiga@gmail.com`.
"@ | Set-Content (Join-Path $rep 'PROCEDIMENTO_LIMPEZA.md') -Encoding UTF8

Write-Host "DONE updated=$($updated.Count) favs=$($favAdded.Count)"
