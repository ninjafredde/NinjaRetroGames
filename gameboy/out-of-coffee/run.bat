@echo off
rem Double-click: build Out of Coffee and play it in SameBoy.
cd /d "%~dp0"
call "%~dp0build.bat"
if errorlevel 1 (
  echo.
  echo Build failed - see above.
  pause
  exit /b 1
)
start "" /d "%~dp0..\tools\sameboy" "%~dp0..\tools\sameboy\sameboy.exe" "%~dp0build\coffee.gb"
