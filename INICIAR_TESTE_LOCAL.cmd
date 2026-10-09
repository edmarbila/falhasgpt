@echo off
setlocal
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Instale o Node.js LTS em https://nodejs.org e abra este arquivo novamente.
  pause
  exit /b 1
)
node server.mjs --open
pause
