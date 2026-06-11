@echo off
chcp 65001 >nul
set EXE=%~dp0CursorBoost.exe
if not exist "%EXE%" set EXE=%~dp0dist\CursorBoost.exe
for /f "delims=" %%D in ('powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"') do set DESK=%%D
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut('%DESK%\Cursor Boost.lnk');$s.TargetPath='%EXE%';$s.WorkingDirectory='%~dp0';$s.Description='Cursor 自救工具';$s.Save()"
echo 桌面快捷方式已创建: Cursor Boost.lnk
pause
