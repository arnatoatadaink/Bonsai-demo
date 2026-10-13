@echo off
setlocal
cd /d "%~dp0"
py -3 "%~dp0generate.py" --output "%~dp0dataset" --target-chars 65000
if errorlevel 1 (echo Dataset generation failed & pause & exit /b 1)
echo Dataset prepared; no inference has been run.
pause
