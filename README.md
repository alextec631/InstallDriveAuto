# InstallDriveAuto - AlexTec

Script simples para instalacao automatica de drivers no Windows usando CMD e PowerShell.

## Como usar

1. Baixe o repositorio em ZIP ou clone pelo Git.
2. Extraia ou coloque todos os drivers dentro da pasta `Drivers`.
3. Clique com o botao direito em `instalar_drivers.bat`.
4. Escolha **Executar como administrador**.
5. Aguarde a instalacao e reinicie o computador.

## Estrutura simples

```text
InstallDriveAuto/
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
- Funciona executando pelo `.bat` ou diretamente pelo PowerShell.

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
