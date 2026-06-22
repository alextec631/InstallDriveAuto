@echo off
title Instalador de Drivers Uteis - AlexTec
color 0A

echo ============================================
echo     INSTALADOR DE DRIVERS UTEIS - ALEXTEC
echo ============================================
echo.

:: Verifica se esta rodando como administrador
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRO] Execute este arquivo como Administrador.
    echo Clique com o botao direito e escolha "Executar como administrador".
    echo.
    pause
    exit /b
)

echo [OK] Permissao de administrador detectada.
echo.

:: Verifica se o PowerShell existe
where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRO] PowerShell nao encontrado neste Windows.
    pause
    exit /b
)

echo Iniciando instalacao automatica dos drivers...
echo.

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0instalar_drivers.ps1"

echo.
echo Processo finalizado.
echo Recomendo reiniciar o computador apos a instalacao.
pause
