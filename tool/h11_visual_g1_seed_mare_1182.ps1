# H11 Visual G1 118.2 — renomear + fotos reais produtos Mare (favoritos/encomendas/live).
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
$headers = @{
  apikey         = $key
  Authorization  = "Bearer $key"
  'Content-Type' = 'application/json'
  Prefer         = 'return=representation'
}

function Invoke-Sb([string]$method, [string]$path, $body = $null) {
  $uri = "$url/rest/v1/$path"
  if ($null -eq $body) {
    return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers
  }
  $json = if ($body -is [string]) { $body } else { ($body | ConvertTo-Json -Depth 8 -Compress) }
  return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -Body $json
}

$catalog = @(
  @{ title = 'Casaco de ganga vintage azul'; photo = 'https://fleaber.pt/fleahub/assets/assets/images/hub_landing/product1.jpg'; price = 24.90 }
  @{ title = 'Mala de cabedal camel'; photo = 'https://fleaber.pt/fleahub/assets/assets/images/hub_landing/product2.jpg'; price = 32.50 }
  @{ title = 'Vestido floral leve'; photo = 'https://fleaber.pt/fleahub/assets/assets/live_covers/fleaber_capa_10.webp'; price = 18.00 }
  @{ title = 'Sapatilhas brancas clássicas'; photo = 'https://fleaber.pt/fleahub/assets/assets/live_covers/fleaber_capa_20.webp'; price = 29.90 }
  @{ title = 'Camisola de lã merino'; photo = 'https://fleaber.pt/fleahub/assets/assets/live_covers/fleaber_capa_30.webp'; price = 22.00 }
  @{ title = 'Calças chino bege'; photo = 'https://fleaber.pt/fleahub/assets/assets/live_covers/fleaber_capa_40.webp'; price = 16.50 }
  @{ title = 'Blusa de seda estampada'; photo = 'https://fleaber.pt/fleahub/assets/assets/live_covers/fleaber_capa_11.webp'; price = 14.90 }
  @{ title = 'Cachecol de lã cinza'; photo = 'https://fleaber.pt/fleahub/assets/assets/live_covers/fleaber_capa_21.webp'; price = 9.50 }
)

Write-Host "Mare=$MareId"

$idSet = [System.Collections.Generic.HashSet[string]]::new()
foreach ($row in @(Invoke-Sb GET ("favorites?user_id=eq.$MareId&select=product_id"))) {
  if ($row.product_id) { [void]$idSet.Add([string]$row.product_id) }
}
foreach ($row in @(Invoke-Sb GET ("orders?or=(seller_id.eq.$MareId,buyer_id.eq.$MareId)&select=product_id&limit=80"))) {
  if ($row.product_id) { [void]$idSet.Add([string]$row.product_id) }
}
foreach ($row in @(Invoke-Sb GET ("products?seller_id=eq.$MareId&select=id&limit=40"))) {
  if ($row.id) { [void]$idSet.Add([string]$row.id) }
}

$ids = @($idSet)
Write-Host "products to refresh: $($ids.Count)"
$updated = @()
$i = 0
foreach ($prodId in $ids) {
  $c = $catalog[$i % $catalog.Count]
  $patch = @{
    title      = $c.title
    image_urls = @($c.photo)
  }
  try {
    $res = Invoke-Sb PATCH ("products?id=eq.$prodId") $patch
    $updated += [pscustomobject]@{ id = $prodId; title = $c.title; photo = $c.photo }
    Write-Host "OK $prodId -> $($c.title)"
  } catch {
    Write-Host "FAIL $prodId : $_"
  }
  $i++
}

# Live items Mare
$lives = @(Invoke-Sb GET ("lives?seller_id=eq.$MareId&select=id&limit=10"))
$liveIds = @($lives | ForEach-Object { $_.id })
$liUpdated = @()
if ($liveIds.Count -gt 0) {
  $in = ($liveIds -join ',')
  $items = @(Invoke-Sb GET ("live_items?live_id=in.($in)&select=id,title,photo_url,ref_code&order=created_at.asc&limit=40"))
  $j = 0
  foreach ($it in $items) {
    $c = $catalog[$j % $catalog.Count]
    $body = @{ title = $c.title; photo_url = $c.photo }
    try {
      Invoke-Sb PATCH ("live_items?id=eq.$($it.id)") $body | Out-Null
      $liUpdated += [pscustomobject]@{ id = $it.id; title = $c.title }
      Write-Host "OK live_item $($it.id) -> $($c.title)"
    } catch {
      Write-Host "FAIL live_item $($it.id): $_"
    }
    $j++
  }
}

$inv = @{
  tag         = 'H11_VISUAL_G1_1182'
  mare        = $MareId
  products    = $updated
  live_items  = $liUpdated
}
$inv | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $rep 'INVENTARIO_DADOS_TESTE_1182.json') -Encoding UTF8
Write-Host "DONE products=$($updated.Count) live_items=$($liUpdated.Count)"
