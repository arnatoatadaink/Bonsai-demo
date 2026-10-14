@echo off
setlocal
cd /d "%~dp0"
if "%~1"=="" (echo Usage: run-variant.bat bonsai^|gemma 11^|29^|47 & exit /b 2)
if "%~2"=="" (echo Missing seed & exit /b 2)
py -3 run.py --model %~1 --data-dir variants/seed_%~2 --question-seed %~2
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
