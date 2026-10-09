@echo off
setlocal
title SnackUP - Aplicacion completa
if not exist "%~dp0runtime\python.exe" (
  echo No se encontro el iniciador. Primero usa "Extraer todo" en el archivo ZIP.
  pause
  exit /b 1
)
"%~dp0runtime\python.exe" -I -B "%~dp0start_snackup.py" %*
if errorlevel 1 (
  echo.
  echo No se pudo iniciar SnackUP. Revisa el mensaje anterior.
  pause
  exit /b 1
)
endlocal
