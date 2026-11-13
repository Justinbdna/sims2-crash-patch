@echo off
setlocal
title Sims 2 Crash Patch - Windows Edition Toolkit
cd /d "%~dp0"

where py >nul 2>&1
if %errorlevel%==0 (
    set "PY_CMD=py -3"
) else (
    where python >nul 2>&1
    if %errorlevel%==0 (
        set "PY_CMD=python"
    ) else (
        echo [!] Python 3 introuvable dans le PATH. Installez Python 3 depuis python.org ou Microsoft Store.
        pause
        exit /b 1
    )
)

:menu
cls
echo ========================================================================
echo   The Sims 2 - Windows Edition Toolkit (100%% separe du patch Mac)
echo ========================================================================
echo.
echo   [1] Diagnostic complet (Ecran Hz, 4GB LAA, OneDrive, Caches, userProps)
echo   [2] Nettoyer les caches corrompus (Groups.cache, Accessory.cache...)
echo   [3] Lancer l'assistant Camera Trackpad (Swipe 2 doigts / F8 / AltGr)
echo   [4] Quitter
echo.
set /p choice=Votre choix (1-4) : 

if "%choice%"=="1" (
    echo.
    %PY_CMD% sims2_windows_toolkit.py scan
    echo.
    pause
    goto menu
)
if "%choice%"=="2" (
    echo.
    %PY_CMD% sims2_windows_toolkit.py clean-cache
    echo.
    pause
    goto menu
)
if "%choice%"=="3" (
    echo.
    %PY_CMD% sims2_trackpad_camera.py
    echo.
    pause
    goto menu
)
if "%choice%"=="4" (
    exit /b 0
)

goto menu
