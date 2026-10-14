@echo off
setlocal
cd /d "%~dp0"
py -3 "%~dp0run-existing.py" --model gemma
set "RC=%ERRORLEVEL%"
echo.
echo Benchmark exit code: %RC%
pause
exit /b %RC%
