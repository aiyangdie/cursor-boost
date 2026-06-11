@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Cursor Boost 诊断（只看不删）
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0boost.ps1" -DiagnoseOnly
echo.
pause
