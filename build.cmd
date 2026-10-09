@echo off
rem One-click build: installs Inno Setup if needed, then builds dist\StorytoldUpdaterSetup.exe
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
pause
