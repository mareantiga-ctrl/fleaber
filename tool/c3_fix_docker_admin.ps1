#Requires -RunAsAdministrator
<#
  Run once as Administrator (right-click → Run with PowerShell).
  Fixes: vmcompute stopped + missing WSL distro → Docker Desktop engine.
  Then from worktree: npx supabase start
#>
$ErrorActionPreference = 'Continue'
Write-Host '=== Fleaber C3 — fix Docker/WSL ==='

Set-Service vmcompute -StartupType Manual
Start-Service vmcompute
Get-Service vmcompute | Format-Table Name, Status, StartType

wsl --update
wsl --set-default-version 2
wsl --install -d Ubuntu

Write-Host 'If Ubuntu installed, complete first-time user setup in the Ubuntu window.'
wsl -l -v

$dd = "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe"
if (Test-Path $dd) {
  Start-Process $dd
  Write-Host 'Docker Desktop starting… wait until engine is green, then:'
  Write-Host '  cd C:\Users\Casa\Desktop\Fleaber\fleaber-c3-unblock'
  Write-Host '  npx supabase start'
} else {
  Write-Host "Docker Desktop not found at $dd"
}

Write-Host 'DONE — reply in chat: DOCKER READY'
