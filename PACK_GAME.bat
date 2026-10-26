@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\pack-windows.ps1"
if errorlevel 1 pause
explorer "%~dp0dist"
