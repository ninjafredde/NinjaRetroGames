@echo off
rem Double-click: build Out of Coffee and play it in SameBoy.
cd /d "%~dp0"
call build.bat
if errorlevel 1 (
  echo.
  echo Build failed - see above.
  pause
  exit /b 1
)
start "" /d "%~dp0tools\sameboy" "%~dp0tools\sameboy\sameboy.exe" "%~dp0build\coffee.gb"
