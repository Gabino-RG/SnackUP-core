@echo off
setlocal
title SnackUP - Paneles de negocios y administracion
if not exist "%~dp0runtime\python.exe" (
  echo Usa Extraer todo antes de abrir este archivo.
  pause
  exit /b 1
)
"%~dp0runtime\python.exe" -I -B "%~dp0review_server.py" %*
if errorlevel 1 (
  echo.
  echo No se pudo iniciar SnackUP. Revisa el mensaje anterior.
  pause
  exit /b 1
)
endlocal
