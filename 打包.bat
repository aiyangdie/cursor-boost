@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Pack Cursor Boost

pip install customtkinter pyinstaller -q

python -m PyInstaller --noconfirm --clean ^
  --onefile --windowed --name CursorBoost ^
  --add-data "engine.ps1;." ^
  --add-data "boost.ps1;." ^
  --add-data "fix-live.ps1;." ^
  --add-data "fix-all.ps1;." ^
  --add-data "fix-cursor-remote.sh;." ^
  --add-data "ssh-config.template.example;." ^
  --add-data "issues.json;." ^
  --add-data "log_scanner.py;." ^
  --add-data "error_catalog.py;." ^
  --add-data "fix-flash.ps1;." ^
  --add-data "fix-remote.bat;." ^
  --add-data "export-report.ps1;." ^
  --add-data "docs;docs" ^
  --add-data "用户收集报错说明.txt;." ^
  --hidden-import customtkinter ^
  --collect-all customtkinter ^
  app.py

if errorlevel 1 exit /b 1
copy /Y "dist\CursorBoost.exe" "CursorBoost.exe" >nul 2>&1
echo Done: dist\CursorBoost.exe
