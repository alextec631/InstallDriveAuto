# InstallDriveAuto

Instalador único, silencioso e automático de drivers para Windows.

A versão 1.3 adiciona identidade visual própria, ícone tecnológico e um painel
moderno com status, progresso e atividade em tempo real.

O driver Samsung Exynos é instalado diretamente pelos pacotes `.inf` assinados,
sem abrir o assistente manual do instalador original.

## Uso

1. Baixe `InstallDriveAuto.exe`.
2. Abra o arquivo.
3. Autorize a execução como administrador.
4. Aguarde a conclusão.

Não é necessário escolher drivers ou responder a instaladores. Os arquivos internos
são extraídos temporariamente, processados e removidos após o encerramento.

O programa possui um motor inteligente de recuperação local que:

- identifica componentes que já estão corretamente instalados;
- interpreta códigos de saída de cada instalador;
- verifica o resultado real no Windows após uma falha;
- tenta uma estratégia silenciosa alternativa quando ela é segura;
- evita apresentar falsos erros quando o componente já está funcionando.

Esse diagnóstico funciona offline e não envia dados do computador para serviços externos.

Os logs permanentes são gravados em:

```text
C:\ProgramData\InstallDriveAuto\Logs
```

## Gerar o EXE

Requisitos:

- Windows PowerShell 5.1;
- módulo `ps2exe`;
- 7-Zip instalado em `C:\Program Files\7-Zip`.
- acesso à internet durante o build para baixar o módulo oficial do LZMA SDK.

Execute:

```powershell
powershell -ExecutionPolicy Bypass -File .\build_exe.ps1
```

O arquivo final será criado em:

```text
dist\InstallDriveAuto.exe
```

## Observação

O EXE final não possui assinatura de código própria. O Windows pode exibir um aviso
do SmartScreen até que o aplicativo seja assinado com um certificado confiável.

O empacotamento usa o módulo de instalação do
[LZMA SDK](https://www.7-zip.org/sdk.html), disponibilizado em domínio público.
