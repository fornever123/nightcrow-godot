@echo off
cd /d "%~dp0"
echo Downloading updates from GitHub (main)...
git pull --ff-only origin main
if errorlevel 1 (
  echo.
  echo Update stopped. Local files were NOT overwritten.
  echo This computer has changes that conflict with GitHub. Ask the AI to merge them.
) else (
  echo.
  echo GitHub download complete.
)
pause
