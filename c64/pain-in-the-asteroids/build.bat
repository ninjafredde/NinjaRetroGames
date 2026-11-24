@echo off
rem Build the game, make a disk image, and run it in VICE.
rem   build.bat        build + run
rem   build.bat norun  build only
setlocal
set ROOT=%~dp0
set VICE=%ROOT%..\tools\GTK3VICE-3.10-win64\bin
if not exist "%ROOT%build" mkdir "%ROOT%build"

java -jar "%ROOT%..\tools\KickAssembler\KickAss.jar" "%ROOT%src\main.asm" -o "%ROOT%build\asteroids.prg" || exit /b 1

if exist "%ROOT%build\wos.d64" del "%ROOT%build\wos.d64"
"%VICE%\c1541.exe" -format "waste of space,01" d64 "%ROOT%build\wos.d64" -write "%ROOT%build\asteroids.prg" "asteroids" >nul || exit /b 1

if /i "%1"=="norun" exit /b 0
start "" "%VICE%\x64sc.exe" -autostart "%ROOT%build\asteroids.prg"
