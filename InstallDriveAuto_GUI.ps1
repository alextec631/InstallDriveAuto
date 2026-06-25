param(
    [switch]$DryRun,
    [switch]$Preview
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedCopy {
    $argumentList = @()
    if ($DryRun) { $argumentList += "-DryRun" }

    try {
        $process = Start-Process -FilePath ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) `
            -ArgumentList $argumentList -Verb RunAs -Wait -PassThru
        exit $process.ExitCode
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "A permissao de administrador e necessaria para instalar os drivers.",
            "InstallDriveAuto",
            "OK",
            "Error"
        ) | Out-Null
        exit 1223
    }
}

if (-not $DryRun -and -not (Test-Admin)) {
    Start-ElevatedCopy
}

$scriptPath = $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($scriptPath)) {
    $scriptPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
}

$BasePath = Split-Path -Parent $scriptPath
if ([string]::IsNullOrWhiteSpace($BasePath)) { $BasePath = (Get-Location).Path }

$DriversPath = Join-Path $BasePath "Drivers"
$LogDirectory = Join-Path $env:ProgramData "InstallDriveAuto\Logs"
$LogPath = Join-Path $LogDirectory ("instalacao_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$script:RebootRequired = $false
$script:FailureCount = 0

New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

function Write-AppLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "OK", "AVISO", "ERRO")]
        [string]$Level = "INFO"
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "HH:mm:ss"), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8

    if ($null -ne $script:txtLog) {
        $script:txtLog.AppendText($line + [Environment]::NewLine)
        $script:txtLog.SelectionStart = $script:txtLog.TextLength
        $script:txtLog.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Set-Status {
    param([string]$Text, [int]$Percent)

    $script:lblStatus.Text = $Text
    $safePercent = [Math]::Max(0, [Math]::Min(100, $Percent))
    $script:lblPercent.Text = "$safePercent%"
    $availableWidth = [Math]::Max(0, $script:progressTrack.ClientSize.Width - 4)
    $script:progressFill.Width = [int]($availableWidth * ($safePercent / 100))
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-InstallerArguments {
    param([System.IO.FileInfo]$Installer)

    switch -Regex ($Installer.Name) {
        '^vcredist2005_' {
            return '/q:a /c:"install /q"'
        }
        '^vcredist2008_' {
            return '/q /norestart'
        }
        '^vcredist2010_' {
            return '/q /norestart'
        }
        '^vcredist20(12|13)_' {
            return '/install /quiet /norestart'
        }
        '^vcredist2015_2017_2019_2022_|^vc_redist\.' {
            return '/install /quiet /norestart'
        }
        '^Oppo USB Driver Setup' {
            return '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
        }
        default {
            return '/S'
        }
    }
}

function Test-SuccessExitCode {
    param([int]$ExitCode)

    # 0: sucesso; 1638: outra versao ja instalada;
    # 1641/3010: sucesso com reinicializacao necessaria.
    return $ExitCode -in @(0, 1638, 1641, 3010)
}

function Get-UninstallEntries {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    return @(Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.DisplayName) })
}

function Test-PackageInstalled {
    param([System.IO.FileInfo]$Installer)

    $name = $Installer.Name
    $entries = @(Get-UninstallEntries)
    $installed = $false
    $evidence = ""

    switch -Regex ($name) {
        '^USBDk\.exe$' {
            $match = $entries | Where-Object { $_.DisplayName -match '^UsbDk Runtime Libraries' } | Select-Object -First 1
            $driver = Get-CimInstance Win32_SystemDriver -Filter "Name='UsbDk'" -ErrorAction SilentlyContinue
            if ($match -or $driver) {
                $installed = $true
                $evidence = if ($match) {
                    "$($match.DisplayName) $($match.DisplayVersion)"
                }
                else {
                    "driver UsbDk presente no Windows"
                }
            }
            break
        }
        '^vcredist2005_x64\.exe$' {
            $match = $entries | Where-Object { $_.DisplayName -match 'Visual C\+\+ 2005.*\(x64\)' } | Select-Object -First 1
            break
        }
        '^vcredist2005_x86\.exe$' {
            $match = $entries | Where-Object {
                $_.DisplayName -match 'Visual C\+\+ 2005 Redistributable' -and
                $_.DisplayName -notmatch '\(x64\)'
            } | Select-Object -First 1
            break
        }
        '^vcredist(2008|2010|2012|2013)_(x64|x86)\.exe$' {
            $year = $Matches[1]
            $architecture = $Matches[2]
            $match = $entries | Where-Object {
                $_.DisplayName -match "Visual C\+\+ $year" -and
                $_.DisplayName -match $architecture
            } | Select-Object -First 1
            break
        }
        '^(vcredist2015_2017_2019_2022|vc_redist)\.(x64|x86)\.exe$|^vcredist2015_2017_2019_2022_(x64|x86)\.exe$' {
            $architecture = if ($Matches[2]) { $Matches[2] } else { $Matches[3] }
            $runtimeKey = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$architecture"
            $runtime = Get-ItemProperty -LiteralPath $runtimeKey -ErrorAction SilentlyContinue
            if (-not $runtime) {
                $runtimeKey = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\$architecture"
                $runtime = Get-ItemProperty -LiteralPath $runtimeKey -ErrorAction SilentlyContinue
            }
            if ($runtime -and $runtime.Installed -eq 1) {
                $installed = $true
                $evidence = "Visual C++ v14 $architecture $($runtime.Version)"
            }
            break
        }
        default {
            return [PSCustomObject]@{ Installed = $false; Evidence = "" }
        }
    }

    if (-not $installed -and $match) {
        $installed = $true
        $evidence = "$($match.DisplayName) $($match.DisplayVersion)"
    }

    return [PSCustomObject]@{ Installed = $installed; Evidence = $evidence }
}

function Get-RecoveryArguments {
    param([System.IO.FileInfo]$Installer)

    switch -Regex ($Installer.Name) {
        '^vcredist2005_' {
            return '/q:a /c:"msiexec /i vcredist.msi /qn /norestart"'
        }
        '^USBDk\.exe$' {
            return '/quiet /norestart'
        }
        '^(vcredist2015_2017_2019_2022|vc_redist)' {
            return '/repair /quiet /norestart'
        }
        default {
            return $null
        }
    }
}

function Install-InfDriver {
    param([System.IO.FileInfo]$Inf)

    if ($DryRun) {
        Write-AppLog "[SIMULACAO] pnputil /add-driver `"$($Inf.FullName)`" /install"
        return
    }

    $output = & pnputil.exe /add-driver $Inf.FullName /install 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { Write-AppLog ([string]$line) }
    }

    if ($exitCode -eq 0) {
        Write-AppLog "Driver INF instalado: $($Inf.Name)" "OK"
    }
    else {
        $script:FailureCount++
        Write-AppLog "Falha no driver INF $($Inf.Name). Codigo: $exitCode" "ERRO"
    }
}

function Install-Executable {
    param([System.IO.FileInfo]$Installer)

    $arguments = Get-InstallerArguments -Installer $Installer

    if ($DryRun) {
        Write-AppLog "IA local: verificaria se $($Installer.Name) ja esta instalado."
        Write-AppLog "[SIMULACAO] `"$($Installer.FullName)`" $arguments" "OK"
        $recoveryArguments = Get-RecoveryArguments -Installer $Installer
        if ($recoveryArguments) {
            Write-AppLog "IA local: em caso de falha, validaria o resultado e tentaria: $recoveryArguments"
        }
        return
    }

    $beforeState = Test-PackageInstalled -Installer $Installer
    if ($beforeState.Installed) {
        Write-AppLog "IA local: $($Installer.Name) ja esta instalado ($($beforeState.Evidence))." "OK"
        return
    }

    Write-AppLog "Instalando $($Installer.Name) com argumentos silenciosos."

    try {
        $process = Start-Process -FilePath $Installer.FullName -ArgumentList $arguments `
            -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
        $exitCode = $process.ExitCode

        if ($exitCode -in @(1641, 3010)) { $script:RebootRequired = $true }

        if (Test-SuccessExitCode -ExitCode $exitCode) {
            Write-AppLog "Concluido: $($Installer.Name). Codigo: $exitCode" "OK"
        }
        else {
            Set-Status "IA analisando $($Installer.Name)..." ([int]$script:lblPercent.Text.TrimEnd('%'))
            Write-AppLog "IA local: codigo $exitCode detectado. Validando o resultado real." "AVISO"

            Start-Sleep -Milliseconds 700
            $afterState = Test-PackageInstalled -Installer $Installer
            if ($afterState.Installed) {
                Write-AppLog "IA local corrigiu o diagnostico: pacote instalado ($($afterState.Evidence))." "OK"
                return
            }

            $recoveryArguments = Get-RecoveryArguments -Installer $Installer
            if ($recoveryArguments) {
                Write-AppLog "IA local: tentando estrategia alternativa segura."
                $retry = Start-Process -FilePath $Installer.FullName -ArgumentList $recoveryArguments `
                    -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop

                if ($retry.ExitCode -in @(1641, 3010)) { $script:RebootRequired = $true }
                $recoveredState = Test-PackageInstalled -Installer $Installer

                if ((Test-SuccessExitCode -ExitCode $retry.ExitCode) -or $recoveredState.Installed) {
                    $detail = if ($recoveredState.Installed) { $recoveredState.Evidence } else { "codigo $($retry.ExitCode)" }
                    Write-AppLog "IA local recuperou a instalacao: $detail." "OK"
                    return
                }

                Write-AppLog "A tentativa alternativa retornou o codigo $($retry.ExitCode)." "AVISO"
            }

            $script:FailureCount++
            Write-AppLog "Falha confirmada apos diagnostico: $($Installer.Name). Codigo: $exitCode" "ERRO"
        }
    }
    catch {
        $afterException = Test-PackageInstalled -Installer $Installer
        if ($afterException.Installed) {
            Write-AppLog "IA local confirmou a instalacao apesar da excecao ($($afterException.Evidence))." "OK"
        }
        else {
            $script:FailureCount++
            Write-AppLog "Falha confirmada ao executar $($Installer.Name): $($_.Exception.Message)" "ERRO"
        }
    }
}

function Start-AutomaticInstallation {
    $script:btnClose.Enabled = $false

    try {
        Set-Content -LiteralPath $LogPath -Value @(
            "==== INSTALLDRIVEAUTO - ALEXTEC ===="
            "Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            "Computador: $env:COMPUTERNAME"
            "Modo: $(if ($DryRun) { 'SIMULACAO' } else { 'AUTOMATICO SILENCIOSO' })"
            "Recuperacao inteligente: ATIVA"
            ""
        ) -Encoding UTF8

        Write-AppLog "Iniciando instalacao automatica com IA local de recuperacao."

        if (-not (Test-Path -LiteralPath $DriversPath)) {
            throw "Os drivers internos nao foram encontrados. Gere novamente o InstallDriveAuto.exe."
        }

        $infFiles = @(Get-ChildItem -LiteralPath $DriversPath -Recurse -File -Filter "*.inf" -ErrorAction SilentlyContinue |
            Sort-Object @{ Expression = { if ($_.FullName -match '[\\/]00_Exynos[\\/]') { 0 } else { 1 } } }, FullName)
        $installers = @(Get-ChildItem -LiteralPath $DriversPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @(".exe", ".msi") } |
            Sort-Object Name)
        $items = @($infFiles) + @($installers)

        if ($items.Count -eq 0) {
            throw "Nenhum driver foi encontrado dentro do pacote."
        }

        Write-AppLog "Pacotes encontrados: $($items.Count)."

        for ($index = 0; $index -lt $items.Count; $index++) {
            $item = $items[$index]
            $percent = 5 + [int](90 * ($index / [Math]::Max(1, $items.Count)))
            $displayName = if ($item.FullName -match '[\\/]00_Exynos[\\/]') {
                "Samsung Exynos - $($item.Name)"
            }
            else {
                $item.Name
            }
            Set-Status "Instalando $($index + 1) de $($items.Count): $displayName" $percent

            if ($item.Extension -eq ".inf") {
                Install-InfDriver -Inf $item
            }
            elseif ($item.Extension -eq ".msi") {
                $arguments = "/i `"$($item.FullName)`" /qn /norestart"
                if ($DryRun) {
                    Write-AppLog "[SIMULACAO] msiexec.exe $arguments" "OK"
                }
                else {
                    $process = Start-Process msiexec.exe -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
                    if ($process.ExitCode -in @(1641, 3010)) { $script:RebootRequired = $true }
                    if (Test-SuccessExitCode $process.ExitCode) {
                        Write-AppLog "Concluido: $($item.Name). Codigo: $($process.ExitCode)" "OK"
                    }
                    else {
                        $script:FailureCount++
                        Write-AppLog "Falha: $($item.Name). Codigo: $($process.ExitCode)" "ERRO"
                    }
                }
            }
            else {
                Install-Executable -Installer $item
            }
        }

        if ($script:FailureCount -eq 0) {
            Set-Status "Instalacao concluida com sucesso" 100
            $message = "Todos os pacotes foram processados com sucesso."
            if ($script:RebootRequired) { $message += "`r`n`r`nReinicie o computador para concluir." }
            Write-AppLog $message.Replace("`r`n", " ") "OK"
            [System.Windows.Forms.MessageBox]::Show($message, "InstallDriveAuto", "OK", "Information") | Out-Null
        }
        else {
            Set-Status "Concluido com $script:FailureCount falha(s)" 100
            $message = "A instalacao terminou com $script:FailureCount falha(s).`r`n`r`nLog: $LogPath"
            Write-AppLog "Processo concluido com falhas. Log: $LogPath" "AVISO"
            [System.Windows.Forms.MessageBox]::Show($message, "InstallDriveAuto", "OK", "Warning") | Out-Null
        }
    }
    catch {
        $script:FailureCount++
        Set-Status "Erro durante a instalacao" 100
        Write-AppLog $_.Exception.Message "ERRO"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "InstallDriveAuto", "OK", "Error") | Out-Null
    }
    finally {
        $script:btnClose.Enabled = $true
        $script:btnLog.Enabled = Test-Path -LiteralPath $LogPath
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "InstallDriveAuto - AlexTec"
$form.ClientSize = New-Object System.Drawing.Size(900, 620)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(8, 15, 28)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$iconPath = Join-Path $BasePath "assets\InstallDriveAuto.ico"
if (Test-Path -LiteralPath $iconPath) {
    $form.Icon = New-Object System.Drawing.Icon($iconPath)
}

$accent = New-Object System.Windows.Forms.Panel
$accent.Dock = "Top"
$accent.Height = 4
$accent.BackColor = [System.Drawing.Color]::FromArgb(0, 220, 190)
$form.Controls.Add($accent)

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 4)
$header.Size = New-Object System.Drawing.Size(900, 112)
$header.BackColor = [System.Drawing.Color]::FromArgb(12, 25, 43)
$form.Controls.Add($header)

$logo = New-Object System.Windows.Forms.PictureBox
$logoPath = Join-Path $BasePath "assets\InstallDriveAuto-logo-256.png"
if (Test-Path -LiteralPath $logoPath) {
    $logo.Image = [System.Drawing.Image]::FromFile($logoPath)
}
$logo.SizeMode = "Zoom"
$logo.Size = New-Object System.Drawing.Size(82, 82)
$logo.Location = New-Object System.Drawing.Point(24, 15)
$header.Controls.Add($logo)

$title = New-Object System.Windows.Forms.Label
$title.Text = "InstallDriveAuto"
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 24, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::White
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(118, 21)
$header.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Driver Intelligence  •  instalação automática e recuperação local"
$subtitle.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(148, 171, 199)
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(121, 66)
$header.Controls.Add($subtitle)

$badge = New-Object System.Windows.Forms.Label
$badge.Text = " IA LOCAL ATIVA "
$badge.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
$badge.ForeColor = [System.Drawing.Color]::FromArgb(75, 255, 194)
$badge.BackColor = [System.Drawing.Color]::FromArgb(15, 63, 66)
$badge.AutoSize = $true
$badge.Padding = New-Object System.Windows.Forms.Padding(8, 5, 8, 5)
$badge.Location = New-Object System.Drawing.Point(746, 36)
$header.Controls.Add($badge)

$statusCard = New-Object System.Windows.Forms.Panel
$statusCard.Location = New-Object System.Drawing.Point(24, 134)
$statusCard.Size = New-Object System.Drawing.Size(852, 116)
$statusCard.BackColor = [System.Drawing.Color]::FromArgb(14, 29, 49)
$form.Controls.Add($statusCard)

$statusCaption = New-Object System.Windows.Forms.Label
$statusCaption.Text = "STATUS DA INSTALAÇÃO"
$statusCaption.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8, [System.Drawing.FontStyle]::Bold)
$statusCaption.ForeColor = [System.Drawing.Color]::FromArgb(0, 218, 205)
$statusCaption.AutoSize = $true
$statusCaption.Location = New-Object System.Drawing.Point(20, 15)
$statusCard.Controls.Add($statusCaption)

$script:lblStatus = New-Object System.Windows.Forms.Label
$script:lblStatus.Text = "Preparando instalacao..."
$script:lblStatus.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$script:lblStatus.ForeColor = [System.Drawing.Color]::White
$script:lblStatus.AutoSize = $true
$script:lblStatus.Location = New-Object System.Drawing.Point(19, 39)
$statusCard.Controls.Add($script:lblStatus)

$script:lblPercent = New-Object System.Windows.Forms.Label
$script:lblPercent.Text = "0%"
$script:lblPercent.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11, [System.Drawing.FontStyle]::Bold)
$script:lblPercent.ForeColor = [System.Drawing.Color]::FromArgb(75, 255, 194)
$script:lblPercent.TextAlign = "MiddleRight"
$script:lblPercent.Size = New-Object System.Drawing.Size(70, 25)
$script:lblPercent.Location = New-Object System.Drawing.Point(758, 37)
$statusCard.Controls.Add($script:lblPercent)

$script:progressTrack = New-Object System.Windows.Forms.Panel
$script:progressTrack.Size = New-Object System.Drawing.Size(812, 14)
$script:progressTrack.Location = New-Object System.Drawing.Point(20, 82)
$script:progressTrack.BackColor = [System.Drawing.Color]::FromArgb(28, 49, 72)
$statusCard.Controls.Add($script:progressTrack)

$script:progressFill = New-Object System.Windows.Forms.Panel
$script:progressFill.Size = New-Object System.Drawing.Size(0, 10)
$script:progressFill.Location = New-Object System.Drawing.Point(2, 2)
$script:progressFill.BackColor = [System.Drawing.Color]::FromArgb(0, 218, 205)
$script:progressTrack.Controls.Add($script:progressFill)

$logCard = New-Object System.Windows.Forms.Panel
$logCard.Location = New-Object System.Drawing.Point(24, 266)
$logCard.Size = New-Object System.Drawing.Size(852, 288)
$logCard.BackColor = [System.Drawing.Color]::FromArgb(14, 29, 49)
$form.Controls.Add($logCard)

$logTitle = New-Object System.Windows.Forms.Label
$logTitle.Text = "ATIVIDADE EM TEMPO REAL"
$logTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8, [System.Drawing.FontStyle]::Bold)
$logTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 218, 205)
$logTitle.AutoSize = $true
$logTitle.Location = New-Object System.Drawing.Point(18, 13)
$logCard.Controls.Add($logTitle)

$script:txtLog = New-Object System.Windows.Forms.TextBox
$script:txtLog.Multiline = $true
$script:txtLog.ScrollBars = "Vertical"
$script:txtLog.ReadOnly = $true
$script:txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$script:txtLog.BorderStyle = "None"
$script:txtLog.BackColor = [System.Drawing.Color]::FromArgb(7, 17, 31)
$script:txtLog.ForeColor = [System.Drawing.Color]::FromArgb(132, 240, 208)
$script:txtLog.Size = New-Object System.Drawing.Size(812, 232)
$script:txtLog.Location = New-Object System.Drawing.Point(20, 40)
$logCard.Controls.Add($script:txtLog)

$script:btnLog = New-Object System.Windows.Forms.Button
$script:btnLog.Text = "Abrir relatório"
$script:btnLog.Enabled = $false
$script:btnLog.FlatStyle = "Flat"
$script:btnLog.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(48, 82, 110)
$script:btnLog.BackColor = [System.Drawing.Color]::FromArgb(18, 39, 62)
$script:btnLog.ForeColor = [System.Drawing.Color]::White
$script:btnLog.Size = New-Object System.Drawing.Size(132, 38)
$script:btnLog.Location = New-Object System.Drawing.Point(600, 570)
$script:btnLog.Add_Click({ Start-Process notepad.exe -ArgumentList "`"$LogPath`"" })
$form.Controls.Add($script:btnLog)

$script:btnClose = New-Object System.Windows.Forms.Button
$script:btnClose.Text = "Fechar"
$script:btnClose.FlatStyle = "Flat"
$script:btnClose.FlatAppearance.BorderSize = 0
$script:btnClose.BackColor = [System.Drawing.Color]::FromArgb(0, 178, 161)
$script:btnClose.ForeColor = [System.Drawing.Color]::White
$script:btnClose.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
$script:btnClose.Size = New-Object System.Drawing.Size(132, 38)
$script:btnClose.Location = New-Object System.Drawing.Point(744, 570)
$script:btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($script:btnClose)

$form.Add_Shown({
    $form.Activate()
    if ($Preview) {
        Set-Status "Interface pronta para iniciar a instalação automática" 42
        $script:txtLog.AppendText("[PREVIEW] Identidade visual InstallDriveAuto v1.3 carregada.`r`n")
        $script:txtLog.AppendText("[INFO] IA local pronta para diagnosticar e recuperar instalações.`r`n")
        $script:btnClose.Enabled = $true
    }
    else {
        Start-AutomaticInstallation
    }
})

[void]$form.ShowDialog()

if ($script:FailureCount -gt 0) { exit 1 }
exit 0
