param(
    [switch]$DryRunPackage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-ExecutionPolicy Bypass -Scope Process -Force

$BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$Source = Join-Path $BasePath "InstallDriveAuto_GUI.ps1"
$Drivers = Join-Path $BasePath "Drivers"
$Assets = Join-Path $BasePath "assets"
$BuildPath = Join-Path $BasePath $(if ($DryRunPackage) { "build-dryrun" } else { "build-prod" })
$PackagePath = Join-Path $BuildPath "package"
$DistPath = Join-Path $BasePath "dist"
$HelperExe = Join-Path $PackagePath "InstallDriveAuto.Runner.exe"
$Archive = Join-Path $BuildPath "payload.7z"
$Config = Join-Path $BuildPath "sfx-config.txt"
$Output = if ($DryRunPackage) {
    Join-Path $BuildPath "InstallDriveAuto-DryRun.exe"
}
else {
    Join-Path $DistPath "InstallDriveAuto.exe"
}
$SevenZip = Join-Path $env:ProgramFiles "7-Zip\7z.exe"
$SdkArchive = Join-Path $BuildPath "lzma-sdk.7z"
$SevenZipSfx = Join-Path $BuildPath "7zSD.sfx"
$SdkUrl = "https://www.7-zip.org/a/lzma2601.7z"
$SdkSha256 = "B860F17F9DF3C0524DD2EF2C639AB5E43AD0006B77B8F7BB6D191BF528536885"

if (-not (Test-Path -LiteralPath $Source)) { throw "Arquivo nao encontrado: $Source" }
if (-not (Test-Path -LiteralPath $Drivers)) { throw "Pasta nao encontrada: $Drivers" }
if (-not (Test-Path -LiteralPath $Assets)) { throw "Pasta nao encontrada: $Assets" }
if (-not (Test-Path -LiteralPath $SevenZip)) { throw "Instale o 7-Zip para gerar o EXE unico." }

if (Test-Path -LiteralPath $BuildPath) {
    $resolvedBuild = (Resolve-Path -LiteralPath $BuildPath).Path
    $resolvedRoot = (Resolve-Path -LiteralPath $BasePath).Path
    if (-not $resolvedBuild.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Diretorio de build fora do projeto."
    }
    Remove-Item -LiteralPath $BuildPath -Recurse -Force
}

New-Item -ItemType Directory -Path $PackagePath -Force | Out-Null
New-Item -ItemType Directory -Path $DistPath -Force | Out-Null
Copy-Item -LiteralPath $Drivers -Destination $PackagePath -Recurse -Force
Copy-Item -LiteralPath $Assets -Destination $PackagePath -Recurse -Force

Write-Host "[1/4] Obtendo modulo oficial de instalacao do 7-Zip..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $SdkUrl -OutFile $SdkArchive -UseBasicParsing
$downloadedHash = (Get-FileHash -LiteralPath $SdkArchive -Algorithm SHA256).Hash
if ($downloadedHash -ne $SdkSha256) {
    throw "O hash do LZMA SDK baixado nao corresponde ao esperado."
}

& $SevenZip e $SdkArchive "-o$BuildPath" "bin\7zSD.sfx" -y | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $SevenZipSfx)) {
    throw "Falha ao extrair o modulo 7zSD.sfx."
}

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Install-Module ps2exe -Scope CurrentUser -Force
}

Import-Module ps2exe -Force

Write-Host "[2/4] Compilando aplicativo..." -ForegroundColor Yellow
Invoke-ps2exe `
    -inputFile $Source `
    -outputFile $HelperExe `
    -iconFile (Join-Path $Assets "InstallDriveAuto.ico") `
    -title "InstallDriveAuto" `
    -description "Instalacao automatica e silenciosa de drivers" `
    -company "AlexTec" `
    -product "InstallDriveAuto" `
    -copyright "AlexTec" `
    -version "1.3.1.0" `
    -noConsole

Write-Host "[3/4] Compactando aplicativo e drivers..." -ForegroundColor Yellow
& $SevenZip a -t7z $Archive "$PackagePath\*" -mx=9 -m0=lzma2 -mmt=on | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Falha ao criar o pacote 7z." }

$runProgram = if ($DryRunPackage) {
    'InstallDriveAuto.Runner.exe -DryRun'
}
else {
    'InstallDriveAuto.Runner.exe'
}

$sfxConfig = @"
;!@Install@!UTF-8!
Title="InstallDriveAuto - AlexTec"
BeginPrompt=""
Progress="yes"
RunProgram="$runProgram"
;!@InstallEnd@!
"@
[System.IO.File]::WriteAllText($Config, $sfxConfig, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "[4/4] Gerando EXE unico..." -ForegroundColor Yellow
$outputStream = [System.IO.File]::Create($Output)
try {
    foreach ($part in @($SevenZipSfx, $Config, $Archive)) {
        $inputStream = [System.IO.File]::OpenRead($part)
        try { $inputStream.CopyTo($outputStream) }
        finally { $inputStream.Dispose() }
    }
}
finally {
    $outputStream.Dispose()
}

$hash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
Write-Host ""
Write-Host "EXE unico criado com sucesso$(if ($DryRunPackage) { ' (simulacao)' } else { '' }):" -ForegroundColor Green
Write-Host $Output -ForegroundColor Cyan
Write-Host "SHA256: $hash" -ForegroundColor DarkGray
