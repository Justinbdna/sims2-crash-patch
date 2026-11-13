@echo off
setlocal
title Sims 2 - Windows Trackpad Camera Helper
cd /d "%~dp0"

where py >nul 2>&1
if %errorlevel%==0 (
    py -3 sims2_trackpad_camera.py %*
) else (
    where python >nul 2>&1
    if %errorlevel%==0 (
        python sims2_trackpad_camera.py %*
    ) else (
        echo [!] Python 3 introuvable dans le PATH.
        pause
        exit /b 1
    )
)

if %errorlevel% neq 0 pause
