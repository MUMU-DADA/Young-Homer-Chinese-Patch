@echo off
chcp 65001 >nul
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0_安装汉化.ps1"
set "code=%errorlevel%"
echo.
pause
exit /b %code%
