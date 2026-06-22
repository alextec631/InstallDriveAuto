@echo off
title Gerador de EXE - InstallDriveAuto
color 0A

echo ============================================
echo     GERADOR DE EXE - INSTALLDRIVEAUTO
echo ============================================
echo.

where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRO] PowerShell nao encontrado.
    pause
    exit /b
)

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0build_exe.ps1"

pause
