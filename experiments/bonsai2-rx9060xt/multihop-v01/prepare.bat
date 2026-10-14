@echo off
setlocal
cd /d "%~dp0"
py -3 generate.py --output dataset --target-chars 80000
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
