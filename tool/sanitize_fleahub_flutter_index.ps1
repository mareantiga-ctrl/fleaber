#Requires -Version 5.1
<#
.SYNOPSIS
  Garante index.html + flutter_bootstrap.js com buildConfig seguro:
  - uma única entrada em builds com compileTarget/renderer/mainJsPath
  - remove entradas vazias {}
  - mainJsPath sem query (cache-bust via stamp/meta)
  - meta fleaber-build + FLEABER_BUILD_STAMP.txt
#>
param(
  [Parameter(Mandatory = $true)][string]$HubDir,
  [Parameter(Mandatory = $true)][string]$Stamp,
  [string]$MainJsPath = 'main.dart.js'
)

$ErrorActionPreference = 'Stop'
$HubDir = (Resolve-Path $HubDir).Path

function Repair-FlutterBuildConfig([string]$text, [string]$mainJsPath) {
  if ($text -notmatch '_flutter\.buildConfig\s*=\s*(\{.*?\});') {
    throw 'buildConfig nao encontrado'
  }
  $json = $Matches[1]
  $cfg = $json | ConvertFrom-Json
  $valid = @()
  foreach ($b in @($cfg.builds)) {
    if ($null -eq $b) { continue }
    $ct = [string]$b.compileTarget
    $ren = [string]$b.renderer
    $mjs = [string]$b.mainJsPath
    if ([string]::IsNullOrWhiteSpace($ct) -or [string]::IsNullOrWhiteSpace($ren)) { continue }
    if ([string]::IsNullOrWhiteSpace($mjs)) { $mjs = $mainJsPath }
    # strip query from path; use clean name
    $mjs = ($mjs -split '\?')[0]
    if ($mjs -ne $mainJsPath) { $mjs = $mainJsPath }
    $valid += [pscustomobject]@{
      compileTarget = $ct
      renderer      = $ren
      mainJsPath    = $mjs
    }
  }
  if ($valid.Count -eq 0) {
    $valid = @(
      [pscustomobject]@{
        compileTarget = 'dart2js'
        renderer      = 'canvaskit'
        mainJsPath    = $mainJsPath
      }
    )
  }
  # Prefer single canvaskit dart2js build
  $pick = $valid | Where-Object { $_.renderer -eq 'canvaskit' -and $_.compileTarget -eq 'dart2js' } | Select-Object -First 1
  if (-not $pick) { $pick = $valid[0] }
  $engine = [string]$cfg.engineRevision
  if ([string]::IsNullOrWhiteSpace($engine)) {
    throw 'engineRevision em falta'
  }
  $newJson = (@{
    engineRevision = $engine
    builds         = @(@{
        compileTarget = [string]$pick.compileTarget
        renderer      = [string]$pick.renderer
        mainJsPath    = [string]$pick.mainJsPath
      })
  } | ConvertTo-Json -Compress -Depth 5)
  # PowerShell ConvertTo-Json may quote keys oddly on older versions — rebuild manually for stable form
  # Sempre local canvaskit no Hub (CDN gstatic → ecrã preto em vários ambientes).
  $newJson = '{"engineRevision":"' + $engine + '","useLocalCanvasKit":true,"builds":[{"compileTarget":"' + $pick.compileTarget + '","renderer":"' + $pick.renderer + '","mainJsPath":"' + $pick.mainJsPath + '"}]}'
  return ($text -replace '_flutter\.buildConfig\s*=\s*\{.*?\};', ("_flutter.buildConfig = $newJson;"))
}

function Ensure-FleaberMeta([string]$html, [string]$stamp) {
  # Remover TODAS as metas fleaber-build (inline ou em linha própria).
  $html = [regex]::Replace($html, '\s*<meta name="fleaber-build"[^>]*>\s*', "`r`n")
  $metaLine = "  <meta name=`"fleaber-build`" content=`"$stamp`" />"
  if ($html -match '<meta name="theme-color"') {
    # Só a primeira theme-color.
    return [regex]::Replace(
      $html,
      '<meta name="theme-color"',
      ($metaLine + "`r`n  <meta name=`"theme-color`""),
      1
    )
  }
  return $html.Replace('</head>', ($metaLine + "`r`n</head>"))
}

$indexPath = Join-Path $HubDir 'index.html'
$bootPath = Join-Path $HubDir 'flutter_bootstrap.js'
if (-not (Test-Path $indexPath)) { throw "falta $indexPath" }

$idx = Get-Content $indexPath -Raw -Encoding UTF8
$idx = Repair-FlutterBuildConfig $idx $MainJsPath
$idx = Ensure-FleaberMeta $idx $Stamp
# UTF8 sem BOM
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($indexPath, $idx, $utf8)

if (Test-Path $bootPath) {
  $boot = Get-Content $bootPath -Raw -Encoding UTF8
  $boot = Repair-FlutterBuildConfig $boot $MainJsPath
  [System.IO.File]::WriteAllText($bootPath, $boot, $utf8)
}

$stampBody = @"
STAMP=$Stamp
NOTE=safe-buildConfig-single-canvaskit;no-empty-builds;mainJsPath-plain;C1-drafts-preserved;H11-118.3-fixes
DATE=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
[System.IO.File]::WriteAllText((Join-Path $HubDir 'FLEABER_BUILD_STAMP.txt'), $stampBody.Trim() + "`n", $utf8)

# Validate
$check = Get-Content $indexPath -Raw -Encoding UTF8
if ($check -notmatch '_flutter\.buildConfig\s*=\s*(\{.*?\});') { throw 'validate: buildConfig missing' }
$cfg2 = $Matches[1] | ConvertFrom-Json
if (@($cfg2.builds).Count -ne 1) { throw "validate: builds count=$(@($cfg2.builds).Count)" }
$b0 = $cfg2.builds[0]
if (-not $b0.compileTarget -or -not $b0.renderer -or -not $b0.mainJsPath) { throw 'validate: incomplete build entry' }
if ($b0.mainJsPath -match '\?') { throw 'validate: mainJsPath still has query' }
if ($check -match 'builds"\s*:\s*\[[^\]]*\{\}') { throw 'validate: empty {} still present' }
if ($check -notmatch [regex]::Escape($Stamp)) { throw 'validate: stamp meta missing' }

Write-Host "OK sanitized HubDir=$HubDir" -ForegroundColor Green
Write-Host "  stamp=$Stamp builds=1 mainJsPath=$($b0.mainJsPath) renderer=$($b0.renderer)"
Select-String -Path $indexPath -Pattern 'fleaber-build|buildConfig' | ForEach-Object {
  $line = $_.Line
  if ($line.Length -gt 200) { $line = $line.Substring(0, 200) + '...' }
  Write-Host "  $line"
}
