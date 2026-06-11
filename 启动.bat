@echo off
chcp 65001 >nul
cd /d "%~dp0"
if exist "CursorBoost.exe" (
  start "" "CursorBoost.exe"
) else if exist "dist\CursorBoost.exe" (
  start "" "dist\CursorBoost.exe"
) else (
  python app.py
)
