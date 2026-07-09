@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_PATH=%SCRIPT_DIR%technician-companion.ps1"

if not exist "%SCRIPT_PATH%" (
  echo technician-companion.ps1 was not found next to this installer.
  exit /b 1
)

start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -InstallStartup %*

exit /b 0
