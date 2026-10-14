@echo off
setlocal
cd /d "%~dp0"
py -3 run.py --model gemma
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
