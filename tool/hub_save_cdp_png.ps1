param(
  [Parameter(Mandatory = $true)][string]$JsonPath,
  [Parameter(Mandatory = $true)][string]$OutPath
)
$j = Get-Content $JsonPath -Raw | ConvertFrom-Json
$data = if ($j.result.data) { $j.result.data } elseif ($j.data) { $j.data } else { $null }
if (-not $data) { throw "No base64 data in $JsonPath" }
$dir = Split-Path $OutPath -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
[IO.File]::WriteAllBytes($OutPath, [Convert]::FromBase64String($data))
Write-Output $OutPath
