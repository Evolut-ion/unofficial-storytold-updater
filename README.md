# Unofficial Storytold Updater

A small Windows tool that installs and updates the portable Windows x64 builds of the
apps published at [github.com/storytold](https://github.com/storytold) (PhotoCraft,
VectorCraft, FilmCraft and friends).

> **Unofficial.** This is a community-made tool. It is not affiliated with, endorsed by,
> or maintained by Storytold or ArtCraft. "Storytold", "ArtCraft" and the app names belong
> to their respective owners and are used here only to say what the tool works with.

## What it does

- Lists every app that has an approved release, with its icon, description, installed
  version and latest version.
- Downloads the latest `*-windows-x64-portable.zip`, verifies it, extracts it, and swaps
  it in for the old copy.
- Deletes the downloaded zip and, once the new copy is in place, the old unzipped folder
  and old zip, so only the new program is left.
- Retargets your existing **taskbar pins, desktop and Start Menu shortcuts** to the new
  copy. Optionally creates a Start Menu shortcut for newly installed apps.
- Optional daily background check.

### What "approved" means

A release is only offered if it is published (not a draft), is not marked pre-release,
contains a `windows-x64-portable.zip`, **and** its `SHA256SUMS.txt` lists that zip.
The download is refused unless its SHA-256 matches. Nothing else is ever executed or
installed.

## Install

Download `StorytoldUpdaterSetup.exe` from the [Releases](../../releases) page and run it.
It installs per-user (no admin rights needed), then lets you pick which apps to install
or update. Compare against `SHA256SUMS.txt` on the release if you like.

The installer is unsigned, so Windows SmartScreen may warn on first run.

Or skip the installer: `StorytoldUpdater.ps1` is a single script.

```powershell
powershell -STA -ExecutionPolicy Bypass -File StorytoldUpdater.ps1          # GUI
powershell -ExecutionPolicy Bypass -File StorytoldUpdater.ps1 -List        # show status
powershell -ExecutionPolicy Bypass -File StorytoldUpdater.ps1 -Update      # update installed apps
powershell -ExecutionPolicy Bypass -File StorytoldUpdater.ps1 -Install photocraft,pdfcraft
```

| Option | Meaning |
|---|---|
| `-InstallRoot <dir>` | Where apps go (default `%LOCALAPPDATA%\Programs\Storytold`) |
| `-KeepOld` | Don't delete old unzipped folders/zips |
| `-RestartExplorer` | Restart Explorer afterwards so taskbar pins refresh |
| `-NoStartShortcut` | Don't create Start Menu shortcuts for new installs |
| `-LogFile <file>` | Also write the log to a file |

Defaults can be stored in `%LOCALAPPDATA%\StorytoldUpdater\config.json`
(the installer writes this for you).

## Behaviour worth knowing

- An app that is currently running is skipped, never killed.
- Existing copies are found from your shortcuts and from folders named like
  `photocraft-0.3.0-windows-x64-portable` in Downloads, Desktop and Documents. Only folders
  and zips with exactly that naming pattern are ever deleted.
- Settings-type files (`.json`, `.toml`, `.ini`, `.cfg`, `.yaml`, `.db`, ...) found in an
  old copy are carried into the new one; binaries are not.
- Renamed products are handled (`printcraft` is now `pdfcraft`).
- Uninstalling the updater leaves the apps it installed in place.

## Network use and privacy

The tool talks only to GitHub: `api.github.com` (release metadata), `github.com`
(downloads) and `raw.githubusercontent.com` (app icons, cached locally). It sends no
telemetry. GitHub's anonymous API allows 60 requests/hour; responses are cached with
ETags, and you can set a `GITHUB_TOKEN` environment variable for a higher limit.

## Build from source

Double-click `build.cmd` (or run `build.ps1`). The build uses [Inno Setup 6](https://jrsoftware.org/isinfo.php) and installs it for you (per-user, via winget, or from jrsoftware.org with a signature check) if it is missing.

```powershell
.\build.ps1 -Version 1.0.0     # -> dist\StorytoldUpdaterSetup.exe + SHA256SUMS.txt
```

Pushing a tag such as `v1.0.0` runs `.github/workflows/release.yml`, which builds the
installer and creates the GitHub Release.

## Licensing

This project is MIT licensed, see [LICENSE](LICENSE). It contains no code, artwork or text
from the Storytold apps; the apps and their icons are downloaded at runtime from their own
repositories and remain under their own licenses. The updater icon is original artwork.
The installer is produced with Inno Setup, whose license allows redistributing the
resulting installers.
