@echo off
rem Build Mushroom for Improvement, make a disk image, and run it in VICE.
rem   build.bat        build + run
rem   build.bat norun  build only
rem Uses the tools in ..\tools (KickAssembler, VICE).
setlocal
set ROOT=%~dp0
set TOOLS=%ROOT%..\tools
set VICE=%TOOLS%\GTK3VICE-3.10-win64\bin
if not exist "%ROOT%build" mkdir "%ROOT%build"

java -jar "%TOOLS%\KickAssembler\KickAss.jar" "%ROOT%src\main.asm" -o "%ROOT%build\mushroom.prg" %2 %3 %4 || exit /b 1

if exist "%ROOT%build\mushroom.d64" del "%ROOT%build\mushroom.d64"
"%VICE%\c1541.exe" -format "waste of space,02" d64 "%ROOT%build\mushroom.d64" -write "%ROOT%build\mushroom.prg" "mushroom" >nul || exit /b 1

if /i "%1"=="norun" exit /b 0
start "" "%VICE%\x64sc.exe" -autostart "%ROOT%build\mushroom.prg"
