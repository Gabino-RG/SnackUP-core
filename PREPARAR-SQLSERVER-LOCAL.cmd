@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup-sqlserver.ps1
if errorlevel 1 pause
