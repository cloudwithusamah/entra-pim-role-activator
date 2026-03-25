@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%Entra-PIM-Role-Activator.ps1"

if not exist "%PS1%" (
    echo ERROR: PowerShell script not found:
    echo %PS1%
    pause
    exit /b 1
)

REM Try PowerShell 7 first
where pwsh >nul 2>nul
if %errorlevel%==0 (
    start "Entra PIM Role Activator" /wait pwsh.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%PS1%"
    exit /b %errorlevel%
)

REM Fallback to Windows PowerShell
where powershell >nul 2>nul
if %errorlevel%==0 (
    start "Entra PIM Role Activator" /wait powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%PS1%"
    exit /b %errorlevel%
)

echo ERROR: Neither PowerShell 7 (pwsh) nor Windows PowerShell was found on this system.
pause
exit /b 1