@echo off
chcp 65001 >nul
cd /d "%~dp0"
title 修复远程服务器 Cursor hooks

echo.
echo  在远程服务器上修复 hooks.json 和 cursor-server 残留
echo  默认: root@121.40.222.49  端口 22
echo  其他主机: fix-remote.bat root@8.137.58.96
echo.

set TARGET=%1
if "%TARGET%"=="" set TARGET=root@121.40.222.49

echo  连接 %TARGET% ...
ssh %TARGET% "bash -s" < "%~dp0fix-cursor-remote.sh"
echo.
if errorlevel 1 (
  echo  失败。检查 IP、端口、密码、安全组。
) else (
  echo  远程修复完成。请重新用 Remote-SSH 连接。
)
pause
