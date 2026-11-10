#Requires -Version 5.1
<#
.SYNOPSIS
  Prepares third_party/flutter_webrtc for C3 / CI clones (path dependency).

.DESCRIPTION
  The Fleaber pubspec uses `flutter_webrtc: path: third_party/flutter_webrtc`.
  That tree is NOT shipped in the GitHub snapshot (local-only / too large for
  casual clones). This script clones a pinned upstream tag into that path.

  Safe: does not touch app lib/, C2 branches, or production secrets.
#>
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$GitUrl = 'https://github.com/flutter-webrtc/flutter-webrtc.git',
  [string]$Tag = '1.4.0'
)

$ErrorActionPreference = 'Stop'
$dest = Join-Path $RepoRoot 'third_party\flutter_webrtc'

Write-Host "RepoRoot=$RepoRoot"
Write-Host "Dest=$dest"
Write-Host "Pin=$GitUrl @$Tag"

New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot 'third_party') | Out-Null

if (Test-Path (Join-Path $dest 'pubspec.yaml')) {
  Write-Host "OK: flutter_webrtc already present"
  exit 0
}

if (Test-Path $dest) {
  Remove-Item -Recurse -Force $dest
}

$tmp = Join-Path $env:TEMP ("fleaber_webrtc_" + [guid]::NewGuid().ToString('N'))
try {
  git clone --depth 1 --branch $Tag $GitUrl $tmp
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  # Copy without .git to keep worktree small / avoid nested repo surprises.
  robocopy $tmp $dest /E /XD .git /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
  if (-not (Test-Path (Join-Path $dest 'pubspec.yaml'))) {
    throw 'Clone/copy failed — pubspec.yaml missing'
  }
  Write-Host "BOOTSTRAP_OK tag=$Tag"
} finally {
  if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
}

exit 0
