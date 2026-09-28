@echo off
cd /d "%~dp0"
where python >nul 2>nul
if errorlevel 1 (
    echo Python isn't installed. Get it from https://www.python.org/downloads/
    echo and tick "Add python.exe to PATH" during the install, then run this again.
    echo.
    pause
    exit /b 1
)
python tools\setup_pc.py
echo.
pause
