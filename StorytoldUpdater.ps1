<#
  Storytold Updater  (unofficial community tool - not affiliated with Storytold / ArtCraft)
  Copyright (c) 2026 OfficialEv0 - MIT License, see LICENSE
  Keeps the portable Windows x64 builds from github.com/storytold up to date.

  GUI (default):   powershell -STA -File StorytoldUpdater.ps1
  Console:         ... -List            show products + status
                   ... -Update          update every installed product that is outdated
                   ... -Install pdfcraft,photocraft   install/update specific products
  Options:         -RestartExplorer     restart Explorer afterwards so taskbar pins refresh
                   -NoStartShortcut     don't create a Start Menu entry for new installs
                   -InstallRoot <dir>   where products go (default: %LOCALAPPDATA%\Programs\Storytold)
                   -KeepOld             leave old unzipped folders/zips in place
                   -LogFile <file>      also append the log here; ends with a DONE line
                   -ListFile <file>     write the product list as tab-separated text and exit
  Defaults for these can live in %LOCALAPPDATA%\StorytoldUpdater\config.json (written by the installer).
  Optional:        set GITHUB_TOKEN to lift the 60 requests/hour anonymous API limit.

  "Approved" release = published (not draft), not a pre-release, has a
  windows-x64-portable.zip AND a SHA256SUMS.txt that lists that zip. The download
  is refused unless its SHA-256 matches.
#>
[CmdletBinding()]
param(
  [switch]$List, [switch]$Update, [string[]]$Install,
  [switch]$RestartExplorer, [switch]$NoStartShortcut,
  [string]$InstallRoot, [switch]$KeepOld, [string]$LogFile, [string]$ListFile
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------- configuration ----------
$Org         = 'storytold'
$DataRoot    = Join-Path $env:LOCALAPPDATA 'StorytoldUpdater'        # cache + state + config
$Cfg = $null; try { $Cfg = Get-Content (Join-Path $DataRoot 'config.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch {}
if (-not $InstallRoot) { $InstallRoot = if ($Cfg -and $Cfg.installRoot) { [string]$Cfg.installRoot } else { Join-Path $env:LOCALAPPDATA 'Programs\Storytold' } }  # one folder per app lives here
if ($Cfg) {
  if (-not $PSBoundParameters.ContainsKey('KeepOld')         -and $Cfg.keepOld)             { $KeepOld = [switch]$true }
  if (-not $PSBoundParameters.ContainsKey('RestartExplorer') -and $Cfg.restartExplorer)     { $RestartExplorer = [switch]$true }
  if (-not $PSBoundParameters.ContainsKey('NoStartShortcut') -and $Cfg.startShortcut -eq $false) { $NoStartShortcut = [switch]$true }
}
$CacheFile   = Join-Path $DataRoot 'http-cache.json'
$StateFile   = Join-Path $DataRoot 'state.json'
$IconDir     = Join-Path $DataRoot 'icons'
$Renames     = @{ printcraft = 'pdfcraft' }                          # old product name -> current
$ZipSuffix   = 'windows-x64-portable'
$LegacyScan  = @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents")
New-Item -ItemType Directory -Force $InstallRoot, $DataRoot, $IconDir | Out-Null

$script:LogSink = { param($m) Write-Host $m; if ($LogFile) { try { Add-Content -LiteralPath $LogFile -Value $m } catch {} } }
function Log([string]$m) { & $script:LogSink $m }

# ---------- tiny JSON stores ----------
function Read-Json($path) {
  if (Test-Path $path) { try { return Get-Content $path -Raw | ConvertFrom-Json } catch {} }
  return $null
}
function ConvertTo-Hash($o) {
  $h = @{}; if ($o) { $o.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value } }; $h
}
$script:Http  = ConvertTo-Hash (Read-Json $CacheFile)
$script:State = ConvertTo-Hash (Read-Json $StateFile)
function Save-Http  { $script:Http  | ConvertTo-Json -Depth 6 | Set-Content $CacheFile -Encoding UTF8 }
function Save-State { $script:State | ConvertTo-Json -Depth 4 | Set-Content $StateFile -Encoding UTF8 }

# PS 5.1 returns a JSON array as ONE object; unroll it so callers get real elements
function ConvertFrom-GhJson([string]$t) { $o = $t | ConvertFrom-Json; foreach ($i in $o) { $i } }

# ---------- GitHub API with ETag cache (304 replies don't count against the rate limit) ----------
function Get-Gh([string]$url) {
  $hdr = @{ 'User-Agent' = 'StorytoldUpdater/1.0'; Accept = 'application/vnd.github+json' }
  if ($env:GITHUB_TOKEN) { $hdr.Authorization = "Bearer $($env:GITHUB_TOKEN)" }
  $cached = $script:Http[$url]
  if ($cached -and $cached.etag) { $hdr['If-None-Match'] = $cached.etag }
  try {
    $r = Invoke-WebRequest $url -Headers $hdr -UseBasicParsing
    $script:Http[$url] = @{ etag = $r.Headers['ETag']; body = $r.Content }
    return (ConvertFrom-GhJson $r.Content)
  } catch {
    $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
    if ($code -eq 304 -and $cached) { return (ConvertFrom-GhJson $cached.body) }
    if ($code -eq 404) { return @() }
    if ($cached) { Log "  (GitHub said $code for $url - using cached data)"; return (ConvertFrom-GhJson $cached.body) }
    throw "GitHub request failed ($code): $url"
  }
}

# ---------- catalog of approved products ----------
function Get-Catalog {
  $repos = @(); $p = 1
  do { $b = @(Get-Gh "https://api.github.com/orgs/$Org/repos?per_page=100&page=$p"); $repos += $b; $p++ } while ($b.Count -eq 100)
  $cut = (Get-Date).AddMonths(-12)
  $repos = $repos | Where-Object { -not $_.fork -and -not $_.archived -and -not $_.private -and [datetime]$_.pushed_at -gt $cut }

  $items = foreach ($repo in $repos) {
    $rels = @(Get-Gh "https://api.github.com/repos/$Org/$($repo.name)/releases?per_page=10")
    foreach ($rel in $rels) {
      if ($rel.draft -or $rel.prerelease) { continue }
      $zip = $rel.assets | Where-Object { $_.name -match "^$([regex]::Escape($repo.name))-.+-$ZipSuffix\.zip$" } | Select-Object -First 1
      $sum = $rel.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1
      if (-not $zip -or -not $sum) { continue }
      $icon = Join-Path $IconDir "$($repo.name).png"
      if (-not (Test-Path $icon)) {
        try { Invoke-WebRequest "https://raw.githubusercontent.com/$Org/$($repo.name)/HEAD/assets/app-icon/hicolor/128x128/apps/ai.storyteller.$($repo.name).png" -OutFile $icon -UseBasicParsing } catch {}
      }
      [pscustomobject]@{
        Name = $repo.name; Description = $(if ($repo.description) { [string]$repo.description } else { "(no description published)" }); Tag = $rel.tag_name
        Version = ($rel.tag_name -replace '^[^0-9]*', ''); Published = $rel.published_at
        ZipName = $zip.name; ZipUrl = $zip.browser_download_url; SumUrl = $sum.browser_download_url
        Icon = $(if (Test-Path $icon) { $icon } else { $null }); Page = $rel.html_url
      }
      break      # newest approved release only
    }
  }
  Save-Http
  $items | Sort-Object Name
}

# ---------- what is installed (managed + legacy unzipped copies) ----------
function Get-AppName([string]$n) { $n = $n.ToLower(); if ($Renames.ContainsKey($n)) { $Renames[$n] } else { $n } }
$LegacyRx = "^(?<n>[a-z0-9]+)-(?<v>\d+(\.\d+)*)-$ZipSuffix$"

function Get-ShortcutFiles {
  $spots = @(
    @{ P = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"; R = $true },
    @{ P = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"; R = $true },
    @{ P = "$env:USERPROFILE\Desktop"; R = $false }, @{ P = "$env:PUBLIC\Desktop"; R = $false },
    @{ P = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned"; R = $true })
  foreach ($s in $spots) {
    if (Test-Path $s.P) { Get-ChildItem $s.P -Filter *.lnk -Recurse:$($s.R) -Depth 3 -ErrorAction SilentlyContinue }
  }
}

function Get-Installed {
  $wsh = New-Object -ComObject WScript.Shell
  $found = @{}      # app -> @{ Version; Legacy = list of dirs; Shortcuts = list of lnk paths }
  function Slot($app) { if (-not $found[$app]) { $found[$app] = @{ Version = $null; Legacy = @(); Shortcuts = @() } }; $found[$app] }

  foreach ($k in $script:State.Keys) {
    $dir = Join-Path $InstallRoot $k
    if (Test-Path (Join-Path $dir "$k.exe")) { (Slot $k).Version = $script:State[$k].version }
  }
  foreach ($root in $LegacyScan) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $LegacyRx } | ForEach-Object {
      $app = Get-AppName $Matches.n; $s = Slot $app
      if (-not $s.Version) { $s.Version = $Matches.v }
      $s.Legacy += $_.FullName
    }
  }
  foreach ($lnk in Get-ShortcutFiles) {
    try { $t = $wsh.CreateShortcut($lnk.FullName).TargetPath } catch { continue }
    if (-not $t) { continue }
    $leaf = [IO.Path]::GetFileNameWithoutExtension($t)
    if ([IO.Path]::GetExtension($t) -ne '.exe') { continue }
    $app = Get-AppName $leaf
    $isLegacy  = $t -match "\\[a-z0-9]+-\d+(\.\d+)*-$([regex]::Escape($ZipSuffix))\\"
    $isManaged = $t.StartsWith($InstallRoot, [StringComparison]::OrdinalIgnoreCase)
    if ($isLegacy -or $isManaged) { (Slot $app).Shortcuts += $lnk.FullName }
  }
  $found
}

function Test-Newer([string]$latest, [string]$have) {
  try { return [version]$latest -gt [version]$have } catch { return $latest -ne $have }
}

# ---------- download + install ----------
function Save-Url([string]$url, [string]$dest, $onProgress) {
  Add-Type -AssemblyName System.Net.Http
  $c = New-Object System.Net.Http.HttpClient
  $c.Timeout = [TimeSpan]::FromMinutes(30)
  $c.DefaultRequestHeaders.UserAgent.ParseAdd('StorytoldUpdater/1.0')
  try {
    $resp = $c.GetAsync($url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    $resp.EnsureSuccessStatusCode() | Out-Null
    $total = $resp.Content.Headers.ContentLength
    $in = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $out = [IO.File]::Create($dest)
    try {
      $buf = New-Object byte[] 262144; $done = 0
      while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) { $out.Write($buf, 0, $n); $done += $n; if ($onProgress) { & $onProgress $done $total } }
    } finally { $out.Dispose(); $in.Dispose() }
  } finally { $c.Dispose() }
}

function Set-Shortcut($lnkPath, $exe) {
  $wsh = New-Object -ComObject WScript.Shell
  $s = $wsh.CreateShortcut($lnkPath)
  $s.TargetPath = $exe; $s.WorkingDirectory = Split-Path $exe; $s.IconLocation = "$exe,0"
  $s.Save()
}

function Install-App($app, $inst, [bool]$startShortcut, $onProgress) {
  $name = $app.Name
  $slot = $inst[$name]                       # $null for a brand-new install
  $legacy    = @($slot.Legacy    | Where-Object { $_ })   # Where-Object: piping $null would still iterate once
  $shortcuts = @($slot.Shortcuts | Where-Object { $_ })
  $exeName = "$name.exe"

  # never touch a copy that is running
  $dirs = @((Join-Path $InstallRoot $name)) + $legacy
  foreach ($proc in Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @($name) + @($Renames.Keys | Where-Object { $Renames[$_] -eq $name }) }) {
    try { $pp = $proc.Path } catch { continue }
    if ($pp -and ($dirs | Where-Object { $pp.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) })) {
      throw "$name is running - close it and try again"
    }
  }

  $work = Join-Path ([IO.Path]::GetTempPath()) ("storytold-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory $work | Out-Null
  try {
    $zip = Join-Path $work $app.ZipName
    Log "  downloading $($app.ZipName)"
    Save-Url $app.ZipUrl $zip $onProgress

    Log "  verifying SHA-256"
    $sumFile = Join-Path $work 'SHA256SUMS.txt'
    Save-Url $app.SumUrl $sumFile $null
    $line = Get-Content $sumFile | Where-Object { $_ -match "\s\*?$([regex]::Escape($app.ZipName))\s*$" } | Select-Object -First 1
    if (-not $line) { throw "SHA256SUMS.txt has no entry for $($app.ZipName) - refusing to install" }
    $want = ($line -split '\s+')[0].ToLower()
    $got  = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    if ($want -ne $got) { throw "checksum mismatch (expected $want, got $got) - refusing to install" }

    Log "  extracting"
    $ex = Join-Path $work 'x'
    Expand-Archive $zip $ex
    $root = $ex
    while ((Get-ChildItem $root -Force | Measure-Object).Count -eq 1 -and (Get-ChildItem $root -Force)[0].PSIsContainer) { $root = (Get-ChildItem $root -Force)[0].FullName }
    if (-not (Test-Path (Join-Path $root $exeName))) { throw "$exeName not found in the archive" }

    # swap into the stable folder (roll back on failure)
    $target = Join-Path $InstallRoot $name
    $backup = "$target.old"
    if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
    if (Test-Path $target) { Move-Item $target $backup }
    try { Move-Item $root $target } catch { if (Test-Path $backup) { Move-Item $backup $target }; throw }

    # carry over settings/data files the old copies had that the release doesn't (never binaries)
    foreach ($old in @($backup) + @($legacy | ForEach-Object {
        $d = $_; while ((Get-ChildItem $d -Force | Measure-Object).Count -eq 1 -and (Get-ChildItem $d -Force)[0].PSIsContainer) { $d = (Get-ChildItem $d -Force)[0].FullName }; $d })) {
      if (-not (Test-Path $old)) { continue }
      Get-ChildItem $old -Recurse -File -Force | Where-Object { $_.Extension -in '.json','.toml','.ini','.cfg','.yaml','.yml','.db','.sqlite' } | ForEach-Object {
        $rel = $_.FullName.Substring($old.Length).TrimStart('\')
        $dst = Join-Path $target $rel
        if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null; Copy-Item $_.FullName $dst }
      }
    }
    $newExe = Join-Path $target $exeName

    # shortcuts: desktop / start menu / taskbar
    $changedTaskbar = $false
    foreach ($lnk in $shortcuts) {
      Set-Shortcut $lnk $newExe; Log "  shortcut updated: $lnk"
      if ($lnk -like '*User Pinned*') { $changedTaskbar = $true }
    }
    if (-not $shortcuts -and $startShortcut) {
      $lnk = Join-Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" "$name.lnk"
      Set-Shortcut $lnk $newExe; Log "  Start Menu shortcut created"
    }

    # cleanup: old managed copy, legacy unzipped folders and their zips (exact names only)
    if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
    foreach ($d in $legacy) {
      if ($KeepOld) { Log "  keeping old install $d"; continue }
      if ((Split-Path $d -Leaf) -notmatch $LegacyRx) { continue }
      Log "  removing old install $d"
      Remove-Item -LiteralPath $d -Recurse -Force
      $oldZip = "$d.zip"
      if (Test-Path -LiteralPath $oldZip) { Log "  removing old zip $oldZip"; Remove-Item -LiteralPath $oldZip -Force }
    }
    $script:State[$name] = @{ version = $app.Version; installed = (Get-Date).ToString('s') }
    Save-State
    return $changedTaskbar
  } finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue      # downloaded zip + extraction temp
  }
}

function Get-Status($app, $inst) {
  $i = $inst[$app.Name]
  if (-not $i) { return @{ Have = $null; Text = 'Not installed'; Action = 'install' } }
  if (-not $i.Version) { return @{ Have = '?'; Text = 'Installed (version unknown)'; Action = 'update' } }
  if (Test-Newer $app.Version $i.Version) { return @{ Have = $i.Version; Text = "Update available"; Action = 'update' } }
  # up to date but still a legacy copy lying around -> consolidate
  if ($i.Legacy.Count) { return @{ Have = $i.Version; Text = 'Up to date (move to managed folder)'; Action = 'update' } }
  @{ Have = $i.Version; Text = 'Up to date'; Action = 'none' }
}

function Invoke-Installs($apps, $inst, $onProgress) {
  $taskbar = $false
  foreach ($a in $apps) {
    Log "[$($a.Name)] -> $($a.Version)"
    try { if (Install-App $a $inst (-not $NoStartShortcut) $onProgress) { $taskbar = $true }; Log "  done" }
    catch { Log "  FAILED: $($_.Exception.Message)" }
  }
  if ($taskbar -and $RestartExplorer) { Log 'restarting Explorer so taskbar pins refresh'; Stop-Process -Name explorer -Force }
  elseif ($taskbar) { Log 'Taskbar pins were retargeted; sign out or restart Explorer if the old icon still shows.' }
}

# ================= console modes =================
if ($List -or $Update -or $Install -or $ListFile) {
  try {
    $cat = @(Get-Catalog); $inst = Get-Installed
    if ($ListFile) {
      $cat | ForEach-Object {
        $s = Get-Status $_ $inst
        $desc = ($_.Description -replace '\s+', ' ') -replace '[^ -~]', '-'
        (@($_.Name, $s.Have, $_.Version, $s.Text, $s.Action, $desc) -join "`t")
      } | Set-Content -LiteralPath $ListFile -Encoding ASCII
    }
    if ($List) {
      $cat | ForEach-Object { $s = Get-Status $_ $inst; '{0,-12} {1,-8} {2,-8} {3}  {4}' -f $_.Name, $s.Have, $_.Version, $s.Text, $_.Description }
    }
    $todo = @()
    if ($Update)  { $todo += $cat | Where-Object { $inst[$_.Name] -and (Get-Status $_ $inst).Action -eq 'update' } }
    if ($Install) { $todo += $cat | Where-Object { $_.Name -in $Install } }
    if ($todo) { Invoke-Installs @($todo | Sort-Object Name -Unique) $inst $null }
  } catch { Log "ERROR: $($_.Exception.Message)" }
  finally { if ($LogFile) { Log 'DONE' } }
  return
}

# ================= GUI =================
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form -Property @{ Text = 'Storytold Updater'; Width = 1100; Height = 760; StartPosition = 'CenterScreen' }
$top  = New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock = 'Top'; Height = 44; Padding = '8,8,8,0' }
function Btn($t) { New-Object Windows.Forms.Button -Property @{ Text = $t; AutoSize = $true; Margin = '0,0,8,0' } }
$bRefresh = Btn 'Refresh'; $bSel = Btn 'Install / update selected'; $bAll = Btn 'Update all installed'
$cExp = New-Object Windows.Forms.CheckBox -Property @{ Text = 'Restart Explorer after (refreshes taskbar pins)'; AutoSize = $true; Margin = '12,5,0,0' }
$top.Controls.AddRange(@($bRefresh, $bSel, $bAll, $cExp))

$imgs = New-Object Windows.Forms.ImageList -Property @{ ImageSize = '48,48'; ColorDepth = 'Depth32Bit' }
$bmpDefault = New-Object Drawing.Bitmap 48, 48
$g = [Drawing.Graphics]::FromImage($bmpDefault); $g.Clear([Drawing.Color]::FromArgb(70, 70, 90)); $g.Dispose()
$imgs.Images.Add('default', $bmpDefault)

$lv = New-Object Windows.Forms.ListView -Property @{ Dock = 'Fill'; View = 'Details'; FullRowSelect = $true; SmallImageList = $imgs; MultiSelect = $true; Font = New-Object Drawing.Font('Segoe UI', 10) }
foreach ($c in @(@('Product', 150), @('Installed', 80), @('Latest', 80), @('Status', 210), @('Description', 520))) { [void]$lv.Columns.Add($c[0], $c[1]) }
$bar = New-Object Windows.Forms.ProgressBar -Property @{ Dock = 'Bottom'; Height = 16 }
$logBox = New-Object Windows.Forms.TextBox -Property @{ Dock = 'Bottom'; Height = 170; Multiline = $true; ReadOnly = $true; ScrollBars = 'Vertical'; Font = New-Object Drawing.Font('Consolas', 9) }
$form.Controls.AddRange(@($lv, $logBox, $bar, $top))

$script:LogSink = { param($m) $logBox.AppendText("$m`r`n"); [Windows.Forms.Application]::DoEvents() }
$onProg = { param($d, $t) if ($t) { $bar.Value = [int][math]::Min(100, 100 * $d / $t) }; [Windows.Forms.Application]::DoEvents() }
$script:Cat = @(); $script:Inst = @{}

function Load-List {
  $form.Cursor = 'WaitCursor'; $bRefresh.Enabled = $bSel.Enabled = $bAll.Enabled = $false
  try {
    Log 'checking GitHub...'
    $script:Cat = @(Get-Catalog); $script:Inst = Get-Installed
    $lv.Items.Clear()
    foreach ($a in $script:Cat) {
      $key = $a.Name
      if ($a.Icon -and -not $imgs.Images.ContainsKey($key)) {
        try { $bytes = [IO.File]::ReadAllBytes($a.Icon); $ms = New-Object IO.MemoryStream(, $bytes); $imgs.Images.Add($key, [Drawing.Image]::FromStream($ms)) } catch {}
      }
      $s = Get-Status $a $script:Inst
      $latest = $a.Version
      $it = New-Object Windows.Forms.ListViewItem($a.Name)
      $it.ImageKey = $(if ($imgs.Images.ContainsKey($key)) { $key } else { 'default' })
      [void]$it.SubItems.Add([string]$s.Have); [void]$it.SubItems.Add($latest); [void]$it.SubItems.Add($s.Text); [void]$it.SubItems.Add($a.Description)
      $it.Tag = $a; $it.ToolTipText = $a.Page
      if ($s.Action -eq 'update') { $it.ForeColor = [Drawing.Color]::DarkOrange } elseif ($s.Action -eq 'none') { $it.ForeColor = [Drawing.Color]::ForestGreen }
      [void]$lv.Items.Add($it)
    }
    Log "$($script:Cat.Count) approved products found."
  } catch { Log "ERROR: $($_.Exception.Message)" }
  finally { $form.Cursor = 'Default'; $bRefresh.Enabled = $bSel.Enabled = $bAll.Enabled = $true }
}
function Run-Installs($apps) {
  if (-not $apps) { return }
  $bRefresh.Enabled = $bSel.Enabled = $bAll.Enabled = $false
  $script:RestartExplorer = $cExp.Checked; Set-Variable RestartExplorer -Scope Script -Value ([switch]$cExp.Checked)
  try { Invoke-Installs $apps $script:Inst $onProg } finally { $bar.Value = 0 }
  Load-List
}
$bRefresh.Add_Click({ Load-List })
$bSel.Add_Click({ Run-Installs @($lv.SelectedItems | ForEach-Object { $_.Tag }) })
$bAll.Add_Click({ Run-Installs @($script:Cat | Where-Object { $script:Inst[$_.Name] -and (Get-Status $_ $script:Inst).Action -eq 'update' }) })
$form.Add_Shown({ Load-List })
[void]$form.ShowDialog()
