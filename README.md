# InstallDriveAuto - AlexTec

Instalador automatico de drivers para Windows, com versao CMD/PowerShell e versao com interface grafica para gerar `.exe`.

## Modo mais simples

1. Baixe o repositorio em ZIP ou clone pelo Git.
2. Extraia ou coloque todos os drivers dentro da pasta `Drivers`.
3. Clique com o botao direito em `instalar_drivers.bat`.
4. Escolha **Executar como administrador**.
5. Aguarde a instalacao e reinicie o computador.

## Modo EXE com log bonito

O projeto tambem tem uma interface grafica em PowerShell:

```text
InstallDriveAuto_GUI.ps1
```

Ela mostra:

- barra de progresso;
- log em tempo real;
- botao para abrir a pasta `Drivers`;
- botao para abrir o log;
- aviso para executar como administrador;
- instalacao automatica de `.inf` com `pnputil`;
- opcao para executar `.exe` e `.msi` encontrados na pasta `Drivers`.

Para gerar o executavel:

1. Clique com o botao direito em `gerar_exe.bat`.
2. Escolha **Executar como administrador** ou execute normalmente.
3. Aguarde ele gerar o arquivo:

```text
InstallDriveAuto.exe
```

Depois disso, coloque os drivers na pasta `Drivers` e rode o `InstallDriveAuto.exe` como administrador.

## Estrutura simples

```text
InstallDriveAuto/
├── InstallDriveAuto.exe
├── InstallDriveAuto_GUI.ps1
├── gerar_exe.bat
├── build_exe.ps1
├── instalar_drivers.bat
├── instalar_drivers.ps1
└── Drivers/
    ├── driver_mtk.inf
    ├── driver_qualcomm.inf
    ├── Samsung_USB_Driver.exe
    └── UsbDk.msi
```

## O que o script faz?

- Procura automaticamente arquivos `.inf` dentro da pasta `Drivers`.
- Instala os drivers usando `pnputil`.
- Gera log da instalacao em `log_instalacao_drivers.txt`.
- Pode executar instaladores `.exe` e `.msi` se o usuario confirmar.
- Funciona pelo `.bat`, pelo `.ps1` ou pela interface `.exe`.

## Drivers que voce pode colocar na pasta Drivers

- MediaTek USB VCOM / Preloader
- Qualcomm HS-USB QDLoader 9008
- Samsung USB Driver
- Motorola USB Driver
- UsbDk Runtime Libraries
- ADB/Fastboot / Android drivers

## Observacao importante

Use apenas drivers de fontes confiaveis. Alguns drivers podem exigir reinicializacao do Windows.

## AlexTec

Projeto criado para facilitar a instalacao de drivers uteis em bancada tecnica.
