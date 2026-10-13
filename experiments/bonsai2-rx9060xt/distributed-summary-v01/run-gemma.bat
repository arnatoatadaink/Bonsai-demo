@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-existing.ps1" -Model gemma
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
