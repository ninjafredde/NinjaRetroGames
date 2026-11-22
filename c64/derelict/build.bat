@echo off
rem Build Derelict, make a disk image, and run it in VICE.
rem   build.bat        build + run
rem   build.bat norun  build only
rem Uses the tools in ..\c64\tools (KickAssembler, VICE).
setlocal
set ROOT=%~dp0
set TOOLS=%ROOT%..\c64\tools
set VICE=%TOOLS%\GTK3VICE-3.10-win64\bin
if not exist "%ROOT%build" mkdir "%ROOT%build"

python "%ROOT%tools\art.py" convert || exit /b 1
java -jar "%TOOLS%\KickAssembler\KickAss.jar" "%ROOT%src\main.asm" -o "%ROOT%build\crawl.prg" %2 %3 %4 %5 %6 %7 || exit /b 1

if exist "%ROOT%build\crawl.d64" del "%ROOT%build\crawl.d64"
"%VICE%\c1541.exe" -format "waste of space,02" d64 "%ROOT%build\crawl.d64" -write "%ROOT%build\crawl.prg" "crawl" >nul || exit /b 1

if /i "%1"=="norun" exit /b 0
start "" "%VICE%\x64sc.exe" -autostart "%ROOT%build\crawl.prg"
