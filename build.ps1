<#
  Builds dist\StorytoldUpdaterSetup.exe and dist\SHA256SUMS.txt.
  Requires Inno Setup 6 (winget install JRSoftware.InnoSetup).
  Usage: .\build.ps1 [-Version 1.2.3]
#>
param([string]$Version = '1.0.0')
$ErrorActionPreference = 'Stop'
$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") |
  Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 not found. Install it with: winget install JRSoftware.InnoSetup' }

& $iscc "/DAppVersion=$Version" (Join-Path $PSScriptRoot 'installer\Storytold-Updater.iss')
if ($LASTEXITCODE) { throw "ISCC failed ($LASTEXITCODE)" }

$dist = Join-Path $PSScriptRoot 'dist'
$exe  = Join-Path $dist 'StorytoldUpdaterSetup.exe'
$hash = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLower()
"$hash  StorytoldUpdaterSetup.exe" | Set-Content (Join-Path $dist 'SHA256SUMS.txt') -Encoding ASCII
Write-Host "Built $exe`nSHA-256 $hash"
