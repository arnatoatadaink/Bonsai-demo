@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" -QuestionsFile "questions-long.json"
set "RC=%ERRORLEVEL%"
echo Long-text benchmark exit code: %RC%
pause
exit /b %RC%
