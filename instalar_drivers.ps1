Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "============================================" -ForegroundColor Green
Write-Host "   INSTALADOR DE DRIVERS UTEIS - ALEXTEC" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

# Verifica administrador
$Admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator"
)

if (-not $Admin) {
    Write-Host "[ERRO] Execute como Administrador." -ForegroundColor Red
    Pause
    exit
}

$BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$DriversPath = Join-Path $BasePath "Drivers"
$LogPath = Join-Path $BasePath "log_instalacao_drivers.txt"

"==== LOG DE INSTALACAO DE DRIVERS ====" | Out-File $LogPath -Encoding UTF8
"Data: $(Get-Date)" | Out-File $LogPath -Append -Encoding UTF8
"Computador: $env:COMPUTERNAME" | Out-File $LogPath -Append -Encoding UTF8
"Usuario: $env:USERNAME" | Out-File $LogPath -Append -Encoding UTF8
"" | Out-File $LogPath -Append -Encoding UTF8

if (!(Test-Path $DriversPath)) {
    Write-Host "[AVISO] Pasta Drivers nao encontrada. Criando automaticamente..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $DriversPath -Force | Out-Null
}

Write-Host "[1/4] Procurando arquivos .INF dentro da pasta Drivers..." -ForegroundColor Yellow

$InfFiles = Get-ChildItem -Path $DriversPath -Recurse -Filter "*.inf" -ErrorAction SilentlyContinue

if ($InfFiles.Count -eq 0) {
    Write-Host "[AVISO] Nenhum arquivo .INF encontrado dentro da pasta Drivers." -ForegroundColor Red
    Write-Host "Coloque todos os drivers extraidos dentro da pasta Drivers e rode novamente." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Estrutura simples:" -ForegroundColor Cyan
    Write-Host "Drivers\"
    Write-Host "  coloque aqui os arquivos .inf, .exe ou .msi dos drivers"
    Pause
    exit
}

Write-Host "[OK] Encontrados $($InfFiles.Count) drivers .INF" -ForegroundColor Green
Write-Host ""

Write-Host "[2/4] Instalando drivers .INF com PNPUTIL..." -ForegroundColor Yellow
Write-Host ""

foreach ($Inf in $InfFiles) {
    Write-Host "Instalando: $($Inf.FullName)" -ForegroundColor Cyan
    "Instalando: $($Inf.FullName)" | Out-File $LogPath -Append -Encoding UTF8

    pnputil /add-driver "$($Inf.FullName)" /install | Tee-Object -FilePath $LogPath -Append

    Write-Host ""
}

Write-Host "[3/4] Procurando instaladores .EXE e .MSI opcionais..." -ForegroundColor Yellow

$Installers = Get-ChildItem -Path $DriversPath -Recurse -Include "*.exe","*.msi" -ErrorAction SilentlyContinue

if ($Installers.Count -gt 0) {
    Write-Host ""
    Write-Host "Foram encontrados instaladores adicionais:" -ForegroundColor Cyan

    foreach ($Installer in $Installers) {
        Write-Host "- $($Installer.Name)"
    }

    Write-Host ""
    $Resp = Read-Host "Deseja executar esses instaladores tambem? Digite S para sim"

    if ($Resp -eq "S" -or $Resp -eq "s") {
        foreach ($Installer in $Installers) {
            Write-Host "Executando: $($Installer.Name)" -ForegroundColor Cyan
            "Executando: $($Installer.FullName)" | Out-File $LogPath -Append -Encoding UTF8

            if ($Installer.Extension -eq ".msi") {
                Start-Process "msiexec.exe" -ArgumentList "/i `"$($Installer.FullName)`" /passive /norestart" -Wait
            } else {
                Start-Process "$($Installer.FullName)" -Wait
            }
        }
    } else {
        Write-Host "Instaladores opcionais ignorados pelo usuario." -ForegroundColor Yellow
    }
} else {
    Write-Host "[OK] Nenhum .EXE ou .MSI encontrado." -ForegroundColor Green
}

Write-Host ""
Write-Host "[4/4] Instalacao finalizada." -ForegroundColor Green
Write-Host "Log salvo em: $LogPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Recomendo reiniciar o computador agora." -ForegroundColor Yellow

Pause
