@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup-postgresql.ps1
if errorlevel 1 goto error
powershell -NoProfile -ExecutionPolicy Bypass -File tools\local-demo.ps1 -Action Stop
if errorlevel 1 goto error
powershell -NoProfile -ExecutionPolicy Bypass -File tools\local-demo.ps1 -Action Start
if errorlevel 1 goto error
exit /b 0
:error
echo No se pudo iniciar SnackUP con PostgreSQL. Revisa el error anterior.
pause
exit /b 1
