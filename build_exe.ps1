Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "============================================" -ForegroundColor Green
Write-Host "   GERADOR DE EXE - INSTALLDRIVEAUTO" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

$BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$Source = Join-Path $BasePath "InstallDriveAuto_GUI.ps1"
$Output = Join-Path $BasePath "InstallDriveAuto.exe"

if (!(Test-Path $Source)) {
    Write-Host "[ERRO] Arquivo InstallDriveAuto_GUI.ps1 nao encontrado." -ForegroundColor Red
    Pause
    exit
}

Write-Host "[1/3] Verificando modulo ps2exe..." -ForegroundColor Yellow

if (!(Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Modulo ps2exe nao encontrado. Instalando..." -ForegroundColor Yellow
    Install-Module ps2exe -Scope CurrentUser -Force
}

Import-Module ps2exe -Force

Write-Host "[2/3] Gerando InstallDriveAuto.exe..." -ForegroundColor Yellow

Invoke-ps2exe `
    -inputFile $Source `
    -outputFile $Output `
    -title "InstallDriveAuto" `
    -description "Instalador automatico de drivers - AlexTec" `
    -company "AlexTec" `
    -product "InstallDriveAuto" `
    -copyright "AlexTec" `
    -version "1.0.0.0" `
    -requireAdmin `
    -noConsole

Write-Host "[3/3] Finalizado." -ForegroundColor Green
Write-Host "EXE criado em: $Output" -ForegroundColor Cyan
Write-Host ""
Write-Host "Agora coloque os drivers dentro da pasta Drivers e execute InstallDriveAuto.exe como Administrador." -ForegroundColor Yellow
Pause
