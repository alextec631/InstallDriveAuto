Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==============================
# InstallDriveAuto GUI - AlexTec
# ==============================

function Test-Admin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($BasePath)) {
    $BasePath = Get-Location
}

$DriversPath = Join-Path $BasePath "Drivers"
$LogPath = Join-Path $BasePath "log_instalacao_drivers.txt"

if (!(Test-Path $DriversPath)) {
    New-Item -ItemType Directory -Path $DriversPath -Force | Out-Null
}

function Write-AppLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $time = Get-Date -Format "HH:mm:ss"
    $line = "[$time] [$Level] $Message"

    $txtLog.AppendText($line + [Environment]::NewLine)
    $txtLog.SelectionStart = $txtLog.Text.Length
    $txtLog.ScrollToCaret()

    $line | Out-File $LogPath -Append -Encoding UTF8
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Status {
    param(
        [string]$Text,
        [int]$Percent
    )

    $lblStatus.Text = $Text
    if ($Percent -lt 0) { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }
    $progress.Value = $Percent
    [System.Windows.Forms.Application]::DoEvents()
}

function Start-DriverInstall {
    $btnInstall.Enabled = $false
    $btnOpenDrivers.Enabled = $false
    $btnOpenLog.Enabled = $false

    try {
        "==== LOG INSTALLDRIVEAUTO - ALEXTEC ====" | Out-File $LogPath -Encoding UTF8
        "Data: $(Get-Date)" | Out-File $LogPath -Append -Encoding UTF8
        "Computador: $env:COMPUTERNAME" | Out-File $LogPath -Append -Encoding UTF8
        "Usuario: $env:USERNAME" | Out-File $LogPath -Append -Encoding UTF8
        "Pasta base: $BasePath" | Out-File $LogPath -Append -Encoding UTF8
        "Pasta drivers: $DriversPath" | Out-File $LogPath -Append -Encoding UTF8
        "" | Out-File $LogPath -Append -Encoding UTF8

        $txtLog.Clear()
        Set-Status "Iniciando verificacoes..." 5
        Write-AppLog "InstallDriveAuto iniciado."

        if (!(Test-Admin)) {
            Write-AppLog "Execute o programa como Administrador." "ERRO"
            [System.Windows.Forms.MessageBox]::Show("Execute o InstallDriveAuto como Administrador.", "Permissao necessaria", "OK", "Error") | Out-Null
            Set-Status "Erro: sem permissao de administrador" 0
            return
        }

        Write-AppLog "Permissao de administrador detectada." "OK"

        if (!(Test-Path $DriversPath)) {
            New-Item -ItemType Directory -Path $DriversPath -Force | Out-Null
            Write-AppLog "Pasta Drivers criada automaticamente." "OK"
        }

        Set-Status "Procurando drivers .INF..." 15
        $InfFiles = Get-ChildItem -Path $DriversPath -Recurse -Filter "*.inf" -ErrorAction SilentlyContinue
        $Installers = Get-ChildItem -Path $DriversPath -Recurse -Include "*.exe","*.msi" -ErrorAction SilentlyContinue

        Write-AppLog "Arquivos .INF encontrados: $($InfFiles.Count)"
        Write-AppLog "Instaladores .EXE/.MSI encontrados: $($Installers.Count)"

        if ($InfFiles.Count -eq 0 -and $Installers.Count -eq 0) {
            Write-AppLog "Nenhum driver encontrado. Coloque .INF, .EXE ou .MSI dentro da pasta Drivers." "AVISO"
            [System.Windows.Forms.MessageBox]::Show("Nenhum driver encontrado. Coloque os drivers dentro da pasta Drivers.", "Drivers nao encontrados", "OK", "Warning") | Out-Null
            Set-Status "Nenhum driver encontrado" 0
            return
        }

        Set-Status "Instalando drivers .INF..." 25

        $totalInf = [Math]::Max($InfFiles.Count, 1)
        $index = 0

        foreach ($Inf in $InfFiles) {
            $index++
            $percent = 25 + [int](($index / $totalInf) * 45)
            Set-Status "Instalando INF $index de $($InfFiles.Count)..." $percent
            Write-AppLog "Instalando INF: $($Inf.FullName)"

            $result = pnputil /add-driver "$($Inf.FullName)" /install 2>&1
            foreach ($line in $result) {
                Write-AppLog $line
            }
        }

        if ($Installers.Count -gt 0) {
            Set-Status "Instaladores adicionais encontrados..." 75
            $answer = [System.Windows.Forms.MessageBox]::Show("Foram encontrados $($Installers.Count) instaladores .EXE/.MSI. Deseja executar tambem?", "Instaladores adicionais", "YesNo", "Question")

            if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
                $totalInst = [Math]::Max($Installers.Count, 1)
                $i = 0

                foreach ($Installer in $Installers) {
                    $i++
                    $percent = 75 + [int](($i / $totalInst) * 20)
                    Set-Status "Executando instalador $i de $($Installers.Count)..." $percent
                    Write-AppLog "Executando instalador: $($Installer.FullName)"

                    if ($Installer.Extension -eq ".msi") {
                        Start-Process "msiexec.exe" -ArgumentList "/i `"$($Installer.FullName)`" /passive /norestart" -Wait
                    } else {
                        Start-Process "$($Installer.FullName)" -Wait
                    }

                    Write-AppLog "Finalizado: $($Installer.Name)" "OK"
                }
            } else {
                Write-AppLog "Instaladores .EXE/.MSI ignorados pelo usuario." "AVISO"
            }
        }

        Set-Status "Instalacao finalizada" 100
        Write-AppLog "Processo finalizado. Recomendo reiniciar o computador." "OK"
        [System.Windows.Forms.MessageBox]::Show("Processo finalizado. Recomendo reiniciar o computador.", "InstallDriveAuto", "OK", "Information") | Out-Null
    }
    catch {
        Write-AppLog $_.Exception.Message "ERRO"
        Set-Status "Erro durante a instalacao" 0
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Erro", "OK", "Error") | Out-Null
    }
    finally {
        $btnInstall.Enabled = $true
        $btnOpenDrivers.Enabled = $true
        $btnOpenLog.Enabled = $true
    }
}

# ==============================
# Interface
# ==============================

$form = New-Object System.Windows.Forms.Form
$form.Text = "InstallDriveAuto - AlexTec"
$form.Size = New-Object System.Drawing.Size(760, 520)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 24)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "InstallDriveAuto"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::LimeGreen
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(25, 20)
$form.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "Instalador automatico de drivers - AlexTec"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$lblSub.ForeColor = [System.Drawing.Color]::WhiteSmoke
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(30, 65)
$form.Controls.Add($lblSub)

$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Text = "Coloque os arquivos .INF, .EXE ou .MSI dentro da pasta Drivers e clique em Instalar."
$lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblInfo.ForeColor = [System.Drawing.Color]::Gainsboro
$lblInfo.AutoSize = $true
$lblInfo.Location = New-Object System.Drawing.Point(30, 98)
$form.Controls.Add($lblInfo)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Instalar Drivers"
$btnInstall.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnInstall.Size = New-Object System.Drawing.Size(170, 42)
$btnInstall.Location = New-Object System.Drawing.Point(30, 135)
$btnInstall.BackColor = [System.Drawing.Color]::FromArgb(0, 140, 70)
$btnInstall.ForeColor = [System.Drawing.Color]::White
$btnInstall.FlatStyle = "Flat"
$btnInstall.Add_Click({ Start-DriverInstall })
$form.Controls.Add($btnInstall)

$btnOpenDrivers = New-Object System.Windows.Forms.Button
$btnOpenDrivers.Text = "Abrir Pasta Drivers"
$btnOpenDrivers.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnOpenDrivers.Size = New-Object System.Drawing.Size(160, 42)
$btnOpenDrivers.Location = New-Object System.Drawing.Point(215, 135)
$btnOpenDrivers.BackColor = [System.Drawing.Color]::FromArgb(55, 55, 55)
$btnOpenDrivers.ForeColor = [System.Drawing.Color]::White
$btnOpenDrivers.FlatStyle = "Flat"
$btnOpenDrivers.Add_Click({
    if (!(Test-Path $DriversPath)) { New-Item -ItemType Directory -Path $DriversPath -Force | Out-Null }
    Start-Process explorer.exe $DriversPath
})
$form.Controls.Add($btnOpenDrivers)

$btnOpenLog = New-Object System.Windows.Forms.Button
$btnOpenLog.Text = "Abrir Log"
$btnOpenLog.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnOpenLog.Size = New-Object System.Drawing.Size(120, 42)
$btnOpenLog.Location = New-Object System.Drawing.Point(390, 135)
$btnOpenLog.BackColor = [System.Drawing.Color]::FromArgb(55, 55, 55)
$btnOpenLog.ForeColor = [System.Drawing.Color]::White
$btnOpenLog.FlatStyle = "Flat"
$btnOpenLog.Add_Click({
    if (Test-Path $LogPath) {
        Start-Process notepad.exe $LogPath
    } else {
        [System.Windows.Forms.MessageBox]::Show("Log ainda nao foi criado.", "InstallDriveAuto", "OK", "Information") | Out-Null
    }
})
$form.Controls.Add($btnOpenLog)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Aguardando inicio..."
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblStatus.ForeColor = [System.Drawing.Color]::WhiteSmoke
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(30, 195)
$form.Controls.Add($lblStatus)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Size = New-Object System.Drawing.Size(680, 22)
$progress.Location = New-Object System.Drawing.Point(30, 220)
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$form.Controls.Add($progress)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(10, 10, 10)
$txtLog.ForeColor = [System.Drawing.Color]::Lime
$txtLog.Size = New-Object System.Drawing.Size(680, 190)
$txtLog.Location = New-Object System.Drawing.Point(30, 260)
$form.Controls.Add($txtLog)

Write-AppLog "Interface carregada. Pasta Drivers: $DriversPath"

[void]$form.ShowDialog()
