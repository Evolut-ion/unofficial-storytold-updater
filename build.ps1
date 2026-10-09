<#
  Builds dist\StorytoldUpdaterSetup.exe and dist\SHA256SUMS.txt.
  If Inno Setup 6 (the tool that compiles the installer) is missing, it is installed
  automatically for the current user - nothing else to set up.
  Usage: .\build.ps1 [-Version 1.2.3]   (or just double-click build.cmd)
#>
param([string]$Version = '1.0.0')
$ErrorActionPreference = 'Stop'

function Find-Iscc {
  @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") |
    Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

$iscc = Find-Iscc
if (-not $iscc) {
  Write-Host 'Inno Setup 6 not found - installing it (per-user, no admin needed)...'
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id JRSoftware.InnoSetup -e --scope user --silent --accept-package-agreements --accept-source-agreements
  } else {
    # no winget: use the official installer from jrsoftware.org (version-pinned, checked by Authenticode signature)
    $tmp = Join-Path $env:TEMP 'innosetup-6.7.3.exe'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe' -OutFile $tmp -UseBasicParsing
    $sig = Get-AuthenticodeSignature $tmp
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Pyrsys B\.V\.') {
      Remove-Item $tmp -Force; throw "Inno Setup installer signature check failed ($($sig.Status)) - not running it"
    }
    Start-Process $tmp -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/CURRENTUSER', '/NORESTART' -Wait
    Remove-Item $tmp -Force
  }
  $iscc = Find-Iscc
  if (-not $iscc) { throw 'Could not install Inno Setup automatically. Get it from https://jrsoftware.org/isdl.php and run again.' }
}

& $iscc "/DAppVersion=$Version" (Join-Path $PSScriptRoot 'installer\Storytold-Updater.iss')
if ($LASTEXITCODE) { throw "ISCC failed ($LASTEXITCODE)" }

$dist = Join-Path $PSScriptRoot 'dist'
$exe  = Join-Path $dist 'StorytoldUpdaterSetup.exe'
$hash = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLower()
"$hash  StorytoldUpdaterSetup.exe" | Set-Content (Join-Path $dist 'SHA256SUMS.txt') -Encoding ASCII
Write-Host "Built $exe`nSHA-256 $hash"
