@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Cursor Boost

:: 优先 GUI；没有 Python 则走命令行
where python >nul 2>&1
if %errorlevel%==0 (
  start "" pythonw "%~dp0cursor_boost.py" 2>nul
  if %errorlevel%==0 exit /b 0
  python "%~dp0cursor_boost.py"
  exit /b 0
)

echo.
echo  Cursor Boost - 命令行模式
echo  将关闭 Cursor 并清理缓存，请先保存文件！
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0boost.ps1"
echo.
set /p R=完成后是否打开 Cursor? (Y/N): 
if /i "%R%"=="Y" start "" "%LOCALAPPDATA%\Programs\cursor\Cursor.exe"
pause
