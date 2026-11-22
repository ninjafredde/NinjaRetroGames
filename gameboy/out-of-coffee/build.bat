@echo off
rem Build Out of Coffee:  build.bat        -> build\coffee.gb
rem                       build.bat run    -> build, then play it in SameBoy
setlocal
cd /d "%~dp0"
python tools\gfx.py || exit /b 1
if not exist build mkdir build
tools\rgbds\rgbasm -Wall -I src -o build\main.o src\main.asm || exit /b 1
tools\rgbds\rgblink -n build\coffee.sym -m build\coffee.map -o build\coffee.gb build\main.o || exit /b 1
tools\rgbds\rgbfix -v -p 0xFF -t OUTOFCOFFEE build\coffee.gb || exit /b 1
echo built build\coffee.gb
if /i "%1"=="run" start "" /d "%~dp0tools\sameboy" "%~dp0tools\sameboy\sameboy.exe" "%~dp0build\coffee.gb"
