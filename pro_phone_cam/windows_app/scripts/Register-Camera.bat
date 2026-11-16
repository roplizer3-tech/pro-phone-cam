@echo off
title Register ProPhone Webcam DirectShow Driver
cd /d "%~dp0"
echo ========================================================
echo    Registering "ProPhone Webcam" into Windows DirectShow
echo ========================================================
echo.
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting Administrator elevation...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)
regsvr32 /s /i:"UnityCaptureName=ProPhone Webcam" "UnityCaptureFilter64.dll"
regsvr32 /s /i:"UnityCaptureName=ProPhone Webcam" "UnityCaptureFilter32.dll"
echo.
echo SUCCESS! "ProPhone Webcam" is now registered as a hardware webcam in Windows!
echo You can now select "ProPhone Webcam" in WhatsApp, Telegram, Zoom, and Chrome.
echo.
pause
