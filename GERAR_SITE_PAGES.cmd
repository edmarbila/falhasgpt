@echo off
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Instale o Node.js 22 ou superior e tente novamente.
  pause
  exit /b 1
)
node build.mjs --require-config
if errorlevel 1 (
  echo Falha. Confira public\project-config.js antes de publicar.
) else (
  echo Pronto. A pasta dist contem os arquivos do site para hospedagem estatica.
)
pause
