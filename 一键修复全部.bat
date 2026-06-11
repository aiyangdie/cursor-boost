@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Cursor 一键修复全部

echo.
echo  ========================================
echo   Cursor 一键修复
echo   - 关闭 Cursor
echo   - 清除 /root 错误工作区（Agent 主因）
echo   - 修复 hooks / 设置 / 缓存
echo  ========================================
echo.
echo  请先保存所有未保存的文件！
pause

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix-all.ps1"
echo.
pause
