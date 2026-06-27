# Instalador de Profile PowerShell

O `Install-PowerShellProfile.ps1` cria um profile modular para uso manual em
terminais PowerShell. Recursos visuais, completions e módulos mais pesados são
carregados somente em sessões interativas. Automações, pipelines e agentes
recebem apenas o core leve.

O instalador não consulta a rede durante a abertura do PowerShell. A
sincronização do `profile-extras.ps1` usa o arquivo publicado neste repositório
e acontece somente quando o comando `update-extras` é executado manualmente.

## Instalação rápida

Execute em um terminal PowerShell:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-PowerShellProfile.ps1
```

Antes de alterar arquivos, o instalador mostra:

- o caminho do profile que será utilizado;
- o diretório dos arquivos modulares;
- a URL configurada para a fonte remota de extras;
- os componentes habilitados e desabilitados por padrão.

Em seguida, oferece três opções:

1. `instalar`: aplica a configuração padrão.
2. `configurar instalação`: pergunta quais componentes devem ser habilitados.
3. `cancelar`: encerra sem instalar.

Depois da instalação, abra um terminal novo ou recarregue o profile:

```powershell
. $PROFILE
```

Instalações anteriores que ainda usam `gist-sync.json` e a URL do Gist devem
executar o instalador novamente. A reinstalação recria o profile core e grava
`extras-sync.json` apontando para o arquivo raw deste repositório.

## Caminhos utilizados

Por padrão, o profile principal é obtido de
`$PROFILE.CurrentUserCurrentHost`. Isso respeita o diretório Documents
configurado para o usuário.

Os arquivos auxiliares ficam ao lado do profile, em `.config\pwsh`:

```text
<diretório do profile>/
|-- Microsoft.PowerShell_profile.ps1
|-- .backups/
`-- .config/pwsh/
    |-- profile-core.ps1
    |-- profile-interactive.ps1
    |-- profile-extras.ps1
    |-- paradox-local-ssh.omp.json
    |-- oh-my-posh-init.ps1
    |-- extras-sync.json
    |-- zoxide-init.ps1
    `-- .backups/
```

O local pode ser alterado pelos parâmetros `-ProfilePath` e `-ConfigDir`.

## Arquitetura do profile

### Profile principal

O `Microsoft.PowerShell_profile.ps1` carrega primeiro o `profile-core.ps1`.
Depois verifica se a sessão é visual e interativa.

O carregamento interativo é interrompido quando alguma destas condições existe:

- entrada ou saída do console redirecionada;
- variável `CI` ou `GITHUB_ACTIONS` definida;
- variável `SKIP_PWSH_PROFILE` definida;
- variável `POWERSHELL_PROFILE_LIGHT` definida;
- host diferente de `ConsoleHost` ou `Visual Studio Code Host`.

Para desabilitar os recursos interativos explicitamente:

```powershell
$env:SKIP_PWSH_PROFILE = '1'
pwsh
```

### profile-core.ps1

É carregado antes do early return e contém apenas funções leves:

- `update-extras`: atualização manual pelo arquivo raw deste repositório;
- `profile-benchmark`: medição do custo do profile;
- `rebuild-zoxide-cache`: reconstrução manual do cache do Zoxide;
- funções internas de detecção, backup e instrumentação.

Nenhuma dessas funções consulta a rede ou executa tarefas pesadas apenas por
ser definida.

### profile-interactive.ps1

É carregado somente em sessões visuais. Contém prompt, PSReadLine,
completions e integrações opcionais.

### profile-extras.ps1

É carregado por último, somente em sessões visuais. Destina-se a aliases,
funções e preferências pessoais mantidas neste repositório.

## Configuração padrão

| Componente              | Padrão   | Comportamento                                            |
| ----------------------- | -------- | -------------------------------------------------------- |
| Oh My Posh              | Ativo    | Usa tema local e script de inicialização.                |
| CaskaydiaCode Nerd Font | Instalar | Fornece glifos para prompt e ícones.                     |
| PSReadLine              | Ativo    | ListView, HistoryAndPlugin e histórico incremental.      |
| CompletionPredictor     | Ativo    | Importado apenas com `Plugin` ou `HistoryAndPlugin`.     |
| Zoxide                  | Ativo    | Disponibiliza `z` e `zi`; não substitui `cd` por padrão. |
| Terminal-Icons          | Ativo    | Importado no primeiro uso de `Get-ChildItem`/`ls`.       |
| WinGet completion       | Ativo    | Registra completion nativa para `winget`.                |
| fzf e PSFzf             | Ativo    | Importa PSFzf no primeiro `Ctrl+r` ou `Ctrl+t`.          |
| posh-git                | Inativo  | Pode ser habilitado com lazy-load no primeiro `git`.     |
| DockerCompletion        | Inativo  | Pode ser habilitado com lazy-load no primeiro `docker`.  |
| GitHub Sync             | Ativo    | Atualização somente por `update-extras`.                 |

No PowerShell 7, módulos são instalados preferencialmente com
`Install-PSResource`. Se PSResourceGet não estiver disponível ou falhar, o
instalador usa `Install-Module` como fallback.

### Identificação da sessão no prompt

O instalador cria `paradox-local-ssh.omp.json`, uma variante local do tema
Paradox. O segmento de sessão não exibe usuário nem nome do computador:

- sessão comum: `local`;
- SSH: `ssh+<IP do servidor>` ou `ssh` quando o IP não está disponível;
- WSL: `wsl+<distribuição>`, por exemplo `wsl+Ubuntu`;
- Remote Desktop: `rdp`;
- GitHub Codespaces: `codespace`;
- VS Code Dev Container: `devcontainer`;
- pod Kubernetes: `kubernetes`;
- Docker ou outro container genérico: `container`;
- PowerShell Remoting/WinRM carregado explicitamente como interativo: `psremoting`;
- Windows Sandbox: `sandbox`.

O profile calcula o rótulo antes de iniciar o Oh My Posh e o disponibiliza em
`POSH_SESSION_LABEL`. O IP do SSH é obtido localmente de `SSH_CONNECTION`;
nenhuma consulta de rede é executada para montar o prompt. Quando mais de uma
condição existe, a classificação mais específica tem prioridade sobre
containers genéricos.

PowerShell Remoting/WinRM, CI e hosts não visuais normalmente não exibem esse
segmento, pois o profile principal encerra antes de carregar o Oh My Posh. O
rótulo `psremoting` existe para o caso em que o profile interativo é carregado
explicitamente nesse contexto.

## Opções configuráveis

Ao escolher `configurar instalação`, é possível ajustar:

- Oh My Posh e fonte Nerd Font;
- PSReadLine;
- estilo de predição: InlineView, ListView ou modo combinado;
- fonte de predição: History, Plugin ou HistoryAndPlugin;
- CompletionPredictor, somente quando a fonte usa plugins;
- compartilhamento incremental do histórico;
- Zoxide e o alias opcional `cd=z`;
- Terminal-Icons;
- posh-git;
- DockerCompletion;
- completion do WinGet;
- fzf e PSFzf;
- GitHub Sync e download inicial dos extras.

## Parâmetros do instalador

| Parâmetro                    | Descrição                                                                       |
| ---------------------------- | ------------------------------------------------------------------------------- |
| `-ProfilePath`               | Caminho do profile principal. O padrão é `$PROFILE.CurrentUserCurrentHost`.     |
| `-ConfigDir`                 | Diretório dos arquivos modulares. O padrão é `.config\pwsh` ao lado do profile. |
| `-ExtrasSourceUrl`           | URL raw do `profile-extras.ps1`; aceita `-ExtrasGistUrl` como alias legado.     |
| `-SkipInitialExtrasDownload` | Não consulta o GitHub durante a instalação e cria os extras locais padrão.      |
| `-Force`                     | Aceita a opção inicial padrão e instala sem perguntas adicionais.               |

Exemplo com caminhos e fonte de extras personalizados:

```powershell
.\Install-PowerShellProfile.ps1 `
    -ProfilePath 'D:\Documentos\PowerShell\Microsoft.PowerShell_profile.ps1' `
    -ConfigDir 'D:\Documentos\PowerShell\.config\pwsh' `
    -ExtrasSourceUrl 'https://raw.githubusercontent.com/usuario/repositorio/main/profile-extras.ps1'
```

## Como funciona o profile-extras

### Instalação inicial

Quando o download inicial está habilitado, o instalador:

1. consulta os metadados HTTP do arquivo raw no GitHub;
2. baixa o conteúdo raw;
3. rejeita conteúdo vazio;
4. valida a sintaxe com o parser oficial do PowerShell;
5. grava `profile-extras.ps1`;
6. salva URL, ETag, Last-Modified e timestamp em `extras-sync.json`.

Se o download ou a validação falhar, o instalador usa o arquivo local padrão.

### Atualização manual

Para verificar se existe uma versão nova sem baixar nem alterar arquivos:

```powershell
update-extras -Status
```

O resultado mostra URL, arquivo local, ETag local, ETag remoto, Last-Modified,
última verificação e o estado da sincronização. Essa operação executa apenas
uma requisição HTTP HEAD.

Para atualizar:

```powershell
update-extras
```

Use `-Force` para baixar mesmo quando o ETag indica que o arquivo está
atualizado:

```powershell
update-extras -Force
```

A atualização segue este fluxo:

1. consulta ETag e Last-Modified remotos;
2. baixa para um arquivo temporário no diretório de configuração;
3. rejeita arquivo vazio;
4. valida o parse completo do script;
5. cria backup do extras atual;
6. substitui o arquivo somente depois da validação;
7. atualiza `extras-sync.json` por arquivo temporário.

O arquivo carregado na sessão atual não muda automaticamente. Depois da
atualização, abra um terminal novo ou execute:

```powershell
. $PROFILE
```

Edições locais em `profile-extras.ps1` serão substituídas na próxima
sincronização. Para torná-las permanentes, faça commit e push do arquivo neste
repositório ou desabilite o GitHub Sync em uma nova instalação.

## Cache do Zoxide

O startup usa `.config\pwsh\zoxide-init.ps1` e não executa
`zoxide --version`. O cache é criado automaticamente apenas quando não existe.

Para reconstruir depois de atualizar ou reconfigurar o Zoxide:

```powershell
rebuild-zoxide-cache
```

## Benchmark

O comando abaixo inicia processos PowerShell separados e compara o custo sem
profile, somente com core e com o profile completo:

```powershell
profile-benchmark
```

Também apresenta tempos individuais para os blocos habilitados, como Oh My
Posh, PSReadLine, CompletionPredictor, Terminal-Icons, WinGet completion,
Zoxide, PSFzf e Extras.

Para aumentar a quantidade de amostras:

```powershell
profile-benchmark -Count 10 -Warmup 2
```

Para consumir os resultados como objetos PowerShell:

```powershell
$resultado = profile-benchmark -Count 10 -PassThru
$resultado.Cenarios
$resultado.Blocos
```

## Backups

Antes de substituir profiles existentes, o instalador cria backups em uma
pasta `.backups` ao lado de cada arquivo. `update-extras` usa a mesma política.

São mantidos os 10 backups mais recentes por arquivo. Os nomes incluem data,
hora e milissegundos:

```text
profile-extras.ps1.bak_20260626_215834_377
```

## Diagnóstico

Confirme qual profile está ativo:

```powershell
$PROFILE.CurrentUserCurrentHost
Test-Path $PROFILE.CurrentUserCurrentHost
```

Confira os comandos carregados pelo core:

```powershell
Get-Command update-extras, profile-benchmark, rebuild-zoxide-cache
```

Confira os arquivos modulares referenciados pelo profile principal:

```powershell
Get-Content $PROFILE.CurrentUserCurrentHost
```

Se um comando novo não aparecer depois de executar o instalador, recarregue o
profile com `. $PROFILE` ou abra uma nova sessão.
