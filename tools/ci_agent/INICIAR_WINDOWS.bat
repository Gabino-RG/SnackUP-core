@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
  py -3 server.py %*
  goto :end
)
where python >nul 2>nul
if not errorlevel 1 (
  python server.py %*
  goto :end
)
echo Instala Python 3.10 o posterior desde https://www.python.org/downloads/
echo Activa Add Python to PATH durante la instalacion y vuelve a abrir este archivo.
:end
pause
