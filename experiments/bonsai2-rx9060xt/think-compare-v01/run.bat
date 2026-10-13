@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1"
set "RC=%ERRORLEVEL%"
echo Benchmark exit code: %RC%
pause
exit /b %RC%
