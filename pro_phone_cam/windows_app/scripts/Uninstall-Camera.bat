@echo off
title Unregister ProPhone Webcam DirectShow Driver
cd /d "%~dp0"
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting Administrator elevation...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)
regsvr32 /u /s "UnityCaptureFilter64.dll"
regsvr32 /u /s "UnityCaptureFilter32.dll"
echo "ProPhone Webcam" unregistered.
pause
