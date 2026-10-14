@echo off
setlocal
cd /d "%~dp0"
py -3 generate_variants.py --output variants --seeds 11 29 47 --target-chars 80000
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
