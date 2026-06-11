@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Cursor 热修复（不关闭 Cursor）

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix-live.ps1"
echo.
pause
