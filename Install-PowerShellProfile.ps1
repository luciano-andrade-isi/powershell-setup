#Requires -Version 5.1
<#
.SYNOPSIS
    Instala um profile modular e rapido para PowerShell.

.DESCRIPTION
    Gera um profile principal com early return para automacoes e divide a
    configuracao visual/interativa em tres arquivos:

    - profile-core.ps1         funcoes leves e comando manual update-extras
    - profile-interactive.ps1  Oh My Posh, PSReadLine, completions e lazy-loads
    - profile-extras.ps1       aliases/funcoes pessoais sincronizaveis por Gist

    O Gist nao e consultado na abertura do terminal. A atualizacao de extras
    acontece apenas quando o usuario executa update-extras.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ExtrasGistUrl = "https://gist.githubusercontent.com/luciano-andrade-isi/32fcd6ec4b0171dd4464b1d0ab37479d/raw/profile-extras.ps1",

    [string]$ConfigDir,

    [string]$ProfilePath = $PROFILE.CurrentUserCurrentHost,

    [switch]$SkipInitialExtrasDownload,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ConfigDir)) {
    $ConfigDir = Join-Path (Split-Path -Path $ProfilePath -Parent) ".config\pwsh"
}

function Write-Step {
    param([string]$Message)
    Write-Host ">> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "OK $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "!! $Message" -ForegroundColor DarkYellow
}

function Write-InstallItem {
    param(
        [string]$Name,
        [string]$Description
    )

    Write-Host "  - $Name" -NoNewline
    Write-Host "  $Description" -ForegroundColor DarkGray
}

function Test-ProfileCommand {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Confirm-Install {
    param([string]$Prompt)
    if ($Force) { return $true }
    $answer = Read-Host "$Prompt [S/n]"
    return [string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[sSyY]'
}

function Confirm-Option {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )

    if ($Force) { return $Default }

    $hint = if ($Default) { "[S/n]" } else { "[s/N]" }
    $answer = Read-Host "$Prompt $hint"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer -match '^[sSyY]'
}

function Select-Option {
    param(
        [string]$Prompt,
        [string[]]$Options,
        [int]$Default = 0
    )

    if ($Force) { return $Default }

    Write-Host ""
    Write-Host $Prompt -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($i -eq $Default) { "=>" } else { "  " }
        Write-Host (" {0} {1}) {2}" -f $marker, ($i + 1), $Options[$i])
    }

    $answer = Read-Host "Escolha (padrao: $($Default + 1))"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }

    $selected = 0
    if (-not [int]::TryParse($answer, [ref]$selected)) { return $Default }
    $selected--
    if ($selected -lt 0 -or $selected -ge $Options.Count) { return $Default }
    return $selected
}

function Refresh-ProcessPath {
    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $env:PATH = @($userPath, $machinePath) -join ';'
}

function Invoke-WingetPackage {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$CommandName,
        [string]$Label = $Id
    )

    if (-not (Test-ProfileCommand "winget")) {
        Write-Warn "winget nao encontrado. Pulando instalacao de $Label."
        return
    }

    try {
        if (Test-ProfileCommand $CommandName) {
            Write-Ok "$Label ja disponivel"
            return
        } else {
            Write-Step "Instalando $Label via winget"
            winget install --id $Id --silent --accept-package-agreements --accept-source-agreements | Out-Null
            Refresh-ProcessPath
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "winget retornou codigo $LASTEXITCODE para $Label."
            return
        }
        Write-Ok "$Label verificado"
    } catch {
        Write-Warn "Falha ao instalar/atualizar ${Label}: $_"
    }
}

function Test-CaskaydiaCodeFontInstalled {
    $registryPaths = @(
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts",
        "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
    )

    foreach ($registryPath in $registryPaths) {
        if (Test-Path -LiteralPath $registryPath) {
            $fontEntry = (Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue).PSObject.Properties |
                Where-Object { $_.Name -like "*Caskaydia*" -or [string]$_.Value -like "*Caskaydia*" } |
                Select-Object -First 1

            if ($fontEntry) { return $true }
        }
    }

    $fontDirs = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"),
        (Join-Path $env:WINDIR "Fonts")
    )

    foreach ($fontDir in $fontDirs) {
        if ((Test-Path -LiteralPath $fontDir) -and
            (Get-ChildItem -LiteralPath $fontDir -Filter "*Caskaydia*" -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            return $true
        }
    }

    return $false
}

function Install-CaskaydiaCodeFont {
    if (Test-CaskaydiaCodeFontInstalled) {
        Write-Ok "Fonte CaskaydiaCode NFM ja instalada"
        return
    }

    Write-Step "Instalando CaskaydiaCode NFM"

    if (Test-ProfileCommand "oh-my-posh") {
        try {
            & oh-my-posh font install CascadiaCode --headless
            if (Test-CaskaydiaCodeFontInstalled) {
                Write-Ok "Fonte CaskaydiaCode instalada/verificada"
                return
            }

            if ($LASTEXITCODE -ne 0) {
                Write-Warn "oh-my-posh font install retornou codigo $LASTEXITCODE."
            }
        } catch {
            Write-Warn "Falha ao instalar fonte via oh-my-posh: $_"
        }
    } else {
        Write-Warn "oh-my-posh nao encontrado. Nao foi possivel instalar a fonte automaticamente."
    }

    if (-not (Test-CaskaydiaCodeFontInstalled)) {
        Write-Warn "Fonte CaskaydiaCode nao foi localizada. Instale manualmente com: oh-my-posh font install CascadiaCode"
    }
}

function Install-ProfileModule {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Version]$MinimumVersion,
        [switch]$AllowPrerelease,
        [switch]$SkipPublisherCheck
    )

    try {
        $existing = Get-Module -ListAvailable -Name $Name |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($existing -and (-not $MinimumVersion -or $existing.Version -ge $MinimumVersion)) {
            Write-Ok "$Name ja instalado: $($existing.Version)"
            return
        }

        $installedWithPSResourceGet = $false
        $installPSResourceCommand = if ($PSVersionTable.PSVersion.Major -ge 7) {
            Get-Command Install-PSResource -ErrorAction SilentlyContinue
        }

        if ($installPSResourceCommand) {
            try {
                Write-Step "Instalando modulo $Name via PSResourceGet"
                $resourceParams = @{
                    Name = $Name
                    Scope = "CurrentUser"
                    ErrorAction = "Stop"
                }
                if ($installPSResourceCommand.Parameters.ContainsKey('TrustRepository')) {
                    $resourceParams.TrustRepository = $true
                }
                if ($installPSResourceCommand.Parameters.ContainsKey('AcceptLicense')) {
                    $resourceParams.AcceptLicense = $true
                }
                if ($MinimumVersion) {
                    $resourceParams.Version = "[$($MinimumVersion.ToString()), ]"
                }
                if ($AllowPrerelease) { $resourceParams.Prerelease = $true }

                Install-PSResource @resourceParams
                $installedWithPSResourceGet = $true
            } catch {
                Write-Warn "PSResourceGet falhou para $Name. Tentando Install-Module. Erro: $_"
            }
        }

        if (-not $installedWithPSResourceGet) {
            if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
                throw "Install-PSResource e Install-Module nao estao disponiveis."
            }

            Write-Step "Instalando modulo $Name via PowerShellGet"
            $moduleParams = @{
                Name = $Name
                Scope = "CurrentUser"
                Force = $true
                ErrorAction = "Stop"
            }
            if ($MinimumVersion) { $moduleParams.MinimumVersion = $MinimumVersion.ToString() }
            if ($AllowPrerelease) { $moduleParams.AllowPrerelease = $true }
            if ($SkipPublisherCheck) { $moduleParams.SkipPublisherCheck = $true }
            Install-Module @moduleParams
        }

        $installed = Get-Module -ListAvailable -Name $Name |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($installed -and (-not $MinimumVersion -or $installed.Version -ge $MinimumVersion)) {
            Write-Ok "$Name instalado/verificado: $($installed.Version)"
        } else {
            Write-Warn "$Name nao foi encontrado apos a instalacao."
        }
    } catch {
        Write-Warn "Falha ao instalar modulo ${Name}: $_"
    }
}

function New-Backup {
    param(
        [string]$Path,
        [ValidateRange(1, 100)][int]$Retention = 10
    )
    if (Test-Path -LiteralPath $Path) {
        $backupDir = Join-Path (Split-Path -Path $Path -Parent) ".backups"
        if (-not (Test-Path -LiteralPath $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }

        $fileName = Split-Path -Path $Path -Leaf
        $backupName = "$fileName.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss_fff')"
        $backup = Join-Path $backupDir $backupName
        Copy-Item -LiteralPath $Path -Destination $backup -Force
        Write-Ok "Backup criado: $backup"

        Get-ChildItem -LiteralPath $backupDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$fileName.bak_*" } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $Retention |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Get-OhMyPoshInfo {
    $exe = $null
    $cmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if ($cmd) { $exe = $cmd.Source }

    if (-not $exe) {
        foreach ($candidate in @(
            "$env:LOCALAPPDATA\Programs\oh-my-posh\bin\oh-my-posh.exe",
            "$env:LOCALAPPDATA\oh-my-posh\oh-my-posh.exe",
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\oh-my-posh.exe",
            "$env:ProgramFiles\oh-my-posh\bin\oh-my-posh.exe"
        )) {
            if (Test-Path -LiteralPath $candidate) {
                $exe = $candidate
                break
            }
        }
    }

    $themesPath = $env:POSH_THEMES_PATH
    if (-not $themesPath -or -not (Test-Path -LiteralPath $themesPath)) {
        foreach ($candidate in @(
            "$env:LOCALAPPDATA\Programs\oh-my-posh\themes",
            "$env:LOCALAPPDATA\oh-my-posh\themes",
            "$env:ProgramFiles\oh-my-posh\themes"
        )) {
            if (Test-Path -LiteralPath $candidate) {
                $themesPath = $candidate
                break
            }
        }
    }

    $theme = if ($themesPath) { Join-Path $themesPath "paradox.omp.json" } else { $null }

    [pscustomobject]@{
        Exe   = $exe
        Theme = $theme
    }
}

function Get-RemoteExtras {
    param([string]$Url)

    $head = Invoke-WebRequest -Uri $Url -Method HEAD -UseBasicParsing -ErrorAction Stop
    $etag = [string]@($head.Headers["ETag"])[0]
    $lastModified = [string]@($head.Headers["Last-Modified"])[0]
    $content = (Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop).Content

    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "O Gist retornou profile-extras.ps1 vazio."
    }

    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput(
        $content,
        [ref]$null,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        $details = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "profile-extras.ps1 remoto possui sintaxe invalida: $details"
    }

    [pscustomobject]@{
        Content      = $content
        ETag         = $etag
        LastModified = $lastModified
    }
}

function ConvertTo-DoubleQuotedLiteral {
    param([string]$Value)
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function ConvertTo-EmptyIfNull {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return "" }
    return $Value
}

$coreFile = Join-Path $ConfigDir "profile-core.ps1"
$interactiveFile = Join-Path $ConfigDir "profile-interactive.ps1"
$extrasFile = Join-Path $ConfigDir "profile-extras.ps1"
$syncFile = Join-Path $ConfigDir "gist-sync.json"
$zoxideCache = Join-Path $ConfigDir "zoxide-init.ps1"
$customOmpTheme = Join-Path $ConfigDir "paradox-local-ssh.omp.json"

Write-Host ""
Write-Host "PowerShell Profile Installer" -ForegroundColor Cyan
Write-Host ""
Write-Host "Profile alvo : $ProfilePath"
Write-Host "Config dir   : $ConfigDir"
Write-Host "Extras gist  : $ExtrasGistUrl"
Write-Host ""

$enableOhMyPosh = $true
$installFont = $true
$configurePSReadLine = $true
$predChoice = 1
$srcChoice = 2
$sharedHistory = $true
$enableZoxide = $true
$zoxideAlias = $false
$installIcons = $true
$enablePoshGit = $false
$installDocker = $false
$installWinGet = $true
$installFzf = $true
$installCompletion = $true
$enableGistSync = $true
$downloadInitialExtras = -not $SkipInitialExtrasDownload

Write-Host "Itens que serao instalados/ativados por padrao:" -ForegroundColor Cyan
Write-InstallItem "Oh My Posh + tema Paradox" "prompt visual rapido com status do Git e contexto"
Write-InstallItem "CaskaydiaCode NFM" "fonte com icones para o prompt e listagens"
Write-InstallItem "PSReadLine" "ListView, HistoryAndPlugin e historico compartilhado"
Write-InstallItem "Zoxide" "atalho inteligente de diretorios com z/zi, sem substituir cd"
Write-InstallItem "Terminal-Icons" "icones em ls/dir carregados apenas no primeiro uso"
Write-InstallItem "WinGet native completion" "autocompletar argumentos do winget"
Write-InstallItem "fzf + PSFzf" "busca interativa no historico e arquivos com Ctrl+r/Ctrl+t"
Write-InstallItem "CompletionPredictor" "predicoes contextuais; usado somente com Plugin/HistoryAndPlugin"
Write-InstallItem "Gist Sync manual por update-extras" "atualiza profile-extras.ps1 somente quando chamado"
if ($downloadInitialExtras) {
    Write-InstallItem "Download inicial do profile-extras.ps1" "baixa os extras uma vez durante a instalacao"
} else {
    Write-InstallItem "profile-extras.ps1 local padrao" "cria extras locais sem consultar o Gist agora"
}
Write-Host ""
Write-Host "Itens desativados por padrao:" -ForegroundColor DarkGray
Write-InstallItem "posh-git" "autocomplete Git por lazy-load no primeiro git"
Write-InstallItem "DockerCompletion" "autocomplete Docker por lazy-load no primeiro docker"
Write-InstallItem "alias cd=z do Zoxide" "faz cd usar o ranking do zoxide"
Write-Host ""

$installAction = Select-Option "Como deseja continuar?" @(
    "instalar"
    "configurar instalacao"
    "cancelar"
) -Default 0

if ($installAction -eq 2) {
    Write-Warn "Instalacao cancelada."
    return
}

if ($installAction -eq 1) {
    Write-Host ""
    Write-Host "Opcoes de instalacao" -ForegroundColor Cyan
    Write-Host ""

    $enableOhMyPosh = Confirm-Option "Instalar/atualizar Oh My Posh e ativar tema Paradox?" $enableOhMyPosh
    $installFont = Confirm-Option "Instalar CaskaydiaCode Nerd Font?" $installFont
    $configurePSReadLine = Confirm-Option "Instalar/configurar PSReadLine?" $configurePSReadLine

    if ($configurePSReadLine) {
        $predChoice = Select-Option "Estilo de sugestao do PSReadLine:" @(
            "InlineView - sugestao aparece apos o cursor"
            "ListView - lista dropdown com historico filtrado"
            "Ambos - InlineView e Tab abre menu de completions"
        ) -Default 1

        $srcChoice = Select-Option "Fonte de predicao do PSReadLine:" @(
            "History - apenas historico de comandos"
            "Plugin - apenas plugins de predicao"
            "HistoryAndPlugin - historico + plugins"
        ) -Default 2

        if ($srcChoice -eq 0) {
            $installCompletion = $false
            Write-Host "CompletionPredictor nao sera instalado porque a fonte selecionada e History." -ForegroundColor DarkGray
        } else {
            $installCompletion = Confirm-Option "Instalar/ativar CompletionPredictor?" $installCompletion
        }

        $sharedHistory = Confirm-Option "Compartilhar historico entre sessoes do PowerShell?" $true
    } else {
        $installCompletion = $false
    }

    $enableZoxide = Confirm-Option "Instalar/atualizar Zoxide e ativar navegacao inteligente?" $enableZoxide
    if ($enableZoxide) {
        $zoxideAlias = Confirm-Option "Substituir 'cd' pelo zoxide (alias cd=z)?" $zoxideAlias
    }

    $installIcons = Confirm-Option "Instalar/ativar Terminal-Icons no primeiro ls/dir?" $installIcons
    $enablePoshGit = Confirm-Option "Instalar/ativar posh-git por lazy-load no primeiro git?" $enablePoshGit
    $installDocker = Confirm-Option "Instalar/ativar DockerCompletion por lazy-load no primeiro docker?" $installDocker
    $installWinGet = Confirm-Option "Configurar autocompletar nativo do WinGet?" $installWinGet
    $installFzf = Confirm-Option "Instalar/ativar fzf + PSFzf para busca interativa?" $installFzf
    $enableGistSync = Confirm-Option "Habilitar Gist Sync manual por update-extras?" $enableGistSync
    $downloadInitialExtras = $false
    if ($enableGistSync -and -not $SkipInitialExtrasDownload) {
        $downloadInitialExtras = Confirm-Option "Baixar profile-extras.ps1 inicial do Gist agora?" $true
    }

    Write-Host ""
    Write-Host "Resumo das escolhas" -ForegroundColor Cyan
    Write-Host "Oh My Posh       : $(if ($enableOhMyPosh) { 'Sim' } else { 'Nao' })"
    Write-Host "Fonte Nerd       : $(if ($installFont) { 'Sim' } else { 'Nao' })"
    Write-Host "PSReadLine       : $(if ($configurePSReadLine) { 'Sim' } else { 'Nao' })"
    if ($configurePSReadLine) {
        Write-Host "PredictionSource : $(@('History', 'Plugin', 'HistoryAndPlugin')[$srcChoice])"
    }
    Write-Host "Zoxide           : $(if ($enableZoxide) { 'Sim' } else { 'Nao' })"
    Write-Host "Zoxide alias cd  : $(if ($zoxideAlias) { 'Sim' } else { 'Nao' })"
    Write-Host "Terminal-Icons   : $(if ($installIcons) { 'Sim' } else { 'Nao' })"
    Write-Host "posh-git         : $(if ($enablePoshGit) { 'Sim' } else { 'Nao' })"
    Write-Host "DockerCompletion : $(if ($installDocker) { 'Sim' } else { 'Nao' })"
    Write-Host "WinGet complete  : $(if ($installWinGet) { 'Sim' } else { 'Nao' })"
    Write-Host "fzf + PSFzf      : $(if ($installFzf) { 'Sim' } else { 'Nao' })"
    Write-Host "CompletionPredict: $(if ($installCompletion) { 'Sim' } else { 'Nao' })"
    Write-Host "Gist Sync manual : $(if ($enableGistSync) { 'Sim' } else { 'Nao' })"
    Write-Host "Download inicial : $(if ($downloadInitialExtras) { 'Sim' } else { 'Nao' })"
    Write-Host ""

    if (-not (Confirm-Install "Instalar com essas opcoes?")) {
        Write-Warn "Instalacao cancelada."
        return
    }
}

$usesPluginPrediction = $configurePSReadLine -and ($srcChoice -in @(1, 2))
if (-not $usesPluginPrediction) {
    $installCompletion = $false
}

if (-not (Test-Path -LiteralPath $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    Write-Ok "Diretorio criado: $ConfigDir"
}

$profileDir = Split-Path -Path $ProfilePath -Parent
if (-not (Test-Path -LiteralPath $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    Write-Ok "Diretorio criado: $profileDir"
}

if ($enableOhMyPosh) {
    Invoke-WingetPackage -Id "JanDeDobbeleer.OhMyPosh" -CommandName "oh-my-posh" -Label "Oh My Posh"
}

if ($installFont) {
    Install-CaskaydiaCodeFont
}

if ($configurePSReadLine) {
    Install-ProfileModule -Name "PSReadLine" -MinimumVersion ([Version]"2.3.0") -AllowPrerelease -SkipPublisherCheck
}

if ($enableZoxide) {
    Invoke-WingetPackage -Id "ajeetdsouza.zoxide" -CommandName "zoxide" -Label "Zoxide"
}

if ($installFzf) {
    Invoke-WingetPackage -Id "junegunn.fzf" -CommandName "fzf" -Label "fzf"
    Install-ProfileModule -Name "PSFzf"
}

if ($installCompletion) { Install-ProfileModule -Name "CompletionPredictor" }
if ($installIcons) { Install-ProfileModule -Name "Terminal-Icons" }
if ($enablePoshGit) { Install-ProfileModule -Name "posh-git" }
if ($installDocker) { Install-ProfileModule -Name "DockerCompletion" }

$omp = if ($enableOhMyPosh) {
    Get-OhMyPoshInfo
} else {
    [pscustomobject]@{ Exe = $null; Theme = $null }
}
if ($enableOhMyPosh -and -not $omp.Exe) {
    Write-Warn "oh-my-posh nao encontrado. O profile interativo fara fallback para Get-Command."
}
if ($enableOhMyPosh -and (-not $omp.Theme -or -not (Test-Path -LiteralPath $omp.Theme))) {
    Write-Warn "Tema paradox.omp.json nao encontrado agora. O profile tentara localizar em runtime."
}

$customOmpThemeContent = $null
if ($enableOhMyPosh -and $omp.Theme -and (Test-Path -LiteralPath $omp.Theme)) {
    try {
        $themeConfig = Get-Content -Raw -LiteralPath $omp.Theme | ConvertFrom-Json -ErrorAction Stop
        $sessionSegment = @(
            $themeConfig.blocks |
                ForEach-Object { $_.segments } |
                Where-Object { $_.type -eq 'session' }
        ) | Select-Object -First 1

        if (-not $sessionSegment) {
            throw "Segmento session nao encontrado no tema Paradox."
        }

        $sessionTemplate = ' {{ if .Env.POSH_SESSION_LABEL }}{{ .Env.POSH_SESSION_LABEL }}{{ else }}local{{ end }} '
        if ($sessionSegment.PSObject.Properties['template']) {
            $sessionSegment.template = $sessionTemplate
        } else {
            $sessionSegment | Add-Member -NotePropertyName template -NotePropertyValue $sessionTemplate
        }

        $customOmpThemeContent = $themeConfig | ConvertTo-Json -Depth 100
        $omp.Theme = $customOmpTheme
    } catch {
        Write-Warn "Nao foi possivel personalizar o segmento de sessao do tema Paradox: $_"
    }
}

$escapedCoreFile = ConvertTo-DoubleQuotedLiteral $coreFile
$escapedInteractiveFile = ConvertTo-DoubleQuotedLiteral $interactiveFile
$escapedExtrasFile = ConvertTo-DoubleQuotedLiteral $extrasFile
$escapedSyncFile = ConvertTo-DoubleQuotedLiteral $syncFile
$escapedZoxideCache = ConvertTo-DoubleQuotedLiteral $zoxideCache
$escapedOmpExe = ConvertTo-DoubleQuotedLiteral (ConvertTo-EmptyIfNull $omp.Exe)
$escapedOmpTheme = ConvertTo-DoubleQuotedLiteral (ConvertTo-EmptyIfNull $omp.Theme)

$coreZoxideBlock = if ($enableZoxide) {
@"
function rebuild-zoxide-cache {
    [CmdletBinding()]
    param([switch]`$Quiet)

    `$zoxideCommand = Get-Command zoxide -ErrorAction SilentlyContinue
    if (-not `$zoxideCommand) {
        Write-Warning '[zoxide] Executavel nao encontrado.'
        return
    }

    `$cacheFile = "$escapedZoxideCache"
    `$temporaryFile = "`$cacheFile.tmp.`$PID"
    try {
        `$content = @(& `$zoxideCommand.Source init powershell)
        if (`$LASTEXITCODE -ne 0 -or `$content.Count -eq 0) {
            throw "zoxide init powershell retornou codigo `$LASTEXITCODE."
        }

        `$content | Set-Content -LiteralPath `$temporaryFile -Encoding UTF8
        Move-Item -LiteralPath `$temporaryFile -Destination `$cacheFile -Force
        if (-not `$Quiet) {
            Write-Host "[zoxide] Cache reconstruido: `$cacheFile" -ForegroundColor Green
        }
    } catch {
        Remove-Item -LiteralPath `$temporaryFile -Force -ErrorAction SilentlyContinue
        Write-Warning "[zoxide] Falha ao reconstruir cache: `$_"
    }
}
"@
} else {
    "# Cache do Zoxide desabilitado nesta instalacao."
}

$coreBenchmarkBlock = @'
function Start-ProfileBlockTimer {
    if ($global:__PROFILE_BENCHMARK_TIMINGS) {
        return [Diagnostics.Stopwatch]::StartNew()
    }
    return $null
}

function Stop-ProfileBlockTimer {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][Diagnostics.Stopwatch]$Watch
    )

    if (-not $Watch -or -not $global:__PROFILE_BENCHMARK_TIMINGS) { return }
    $Watch.Stop()
    $global:__PROFILE_BENCHMARK_TIMINGS.Add([pscustomobject]@{
        Name = $Name
        ElapsedMs = $Watch.Elapsed.TotalMilliseconds
    })
}

function Profile-Benchmark {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 50)][int]$Count = 5,
        [ValidateRange(0, 10)][int]$Warmup = 1,
        [switch]$PassThru
    )

    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    $pwshPath = if ($pwshCommand) {
        $pwshCommand.Source
    } else {
        (Get-Process -Id $PID -ErrorAction Stop).Path
    }
    $coreFile = Join-Path $script:PROFILE_CONFIG_DIR 'profile-core.ps1'
    $interactiveFile = Join-Path $script:PROFILE_CONFIG_DIR 'profile-interactive.ps1'
    $extrasFile = Join-Path $script:PROFILE_CONFIG_DIR 'profile-extras.ps1'

    foreach ($file in @($coreFile, $interactiveFile, $extrasFile)) {
        if (-not (Test-Path -LiteralPath $file)) {
            throw "Arquivo de profile nao encontrado: $file"
        }
    }

    function ConvertTo-ProfileEncodedCommand {
        param([Parameter(Mandatory)][string]$Script)
        [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    }

    function Invoke-ProfileBenchmarkSample {
        param(
            [Parameter(Mandatory)][string]$FilePath,
            [Parameter(Mandatory)][string]$Script
        )

        $timingFile = $null
        try {
            if ($Script.Contains('__PROFILE_TIMING_FILE__')) {
                $timingFile = Join-Path ([IO.Path]::GetTempPath()) ("pwsh-profile-{0}.json" -f [guid]::NewGuid())
                $quotedTimingFile = "'$($timingFile.Replace("'", "''"))'"
                $Script = $Script.Replace("'__PROFILE_TIMING_FILE__'", $quotedTimingFile)
            }

            $encodedCommand = ConvertTo-ProfileEncodedCommand $Script
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $process = Start-Process -FilePath $FilePath `
                -ArgumentList @('-NoLogo', '-NoProfile', '-EncodedCommand', $encodedCommand) `
                -NoNewWindow -Wait -PassThru
            $watch.Stop()

            if ($process.ExitCode -ne 0) {
                throw "Processo de benchmark terminou com codigo $($process.ExitCode)."
            }

            $blockTimings = @()
            if ($timingFile -and (Test-Path -LiteralPath $timingFile)) {
                $blockTimings = @(Get-Content -Raw -LiteralPath $timingFile | ConvertFrom-Json)
            }
            [pscustomobject]@{
                TotalMs = $watch.Elapsed.TotalMilliseconds
                BlockTimings = $blockTimings
            }
        } finally {
            if ($timingFile) { Remove-Item -LiteralPath $timingFile -Force -ErrorAction SilentlyContinue }
        }
    }

    function Get-ProfileMedian {
        param([double[]]$Values)
        $ordered = @($Values | Sort-Object)
        $middle = [int][Math]::Floor($ordered.Count / 2)
        if (($ordered.Count % 2) -eq 1) { return $ordered[$middle] }
        return ($ordered[$middle - 1] + $ordered[$middle]) / 2
    }

    $quotePath = {
        param([string]$Path)
        "'$($Path.Replace("'", "''"))'"
    }
    $quotedCore = & $quotePath $coreFile
    $quotedInteractive = & $quotePath $interactiveFile
    $quotedExtras = & $quotePath $extrasFile

    $quietPrefix = "`$WarningPreference = 'SilentlyContinue';"
    $fullProfileScript = @"
$quietPrefix
`$global:__PROFILE_BENCHMARK_TIMINGS = [System.Collections.Generic.List[object]]::new()
`$__coreWatch = [Diagnostics.Stopwatch]::StartNew()
. $quotedCore
`$__coreWatch.Stop()
`$global:__PROFILE_BENCHMARK_TIMINGS.Add([pscustomobject]@{ Name = 'Core'; ElapsedMs = `$__coreWatch.Elapsed.TotalMilliseconds })
. $quotedInteractive
`$__extrasWatch = [Diagnostics.Stopwatch]::StartNew()
. $quotedExtras
`$__extrasWatch.Stop()
`$global:__PROFILE_BENCHMARK_TIMINGS.Add([pscustomobject]@{ Name = 'Extras'; ElapsedMs = `$__extrasWatch.Elapsed.TotalMilliseconds })
`$global:__PROFILE_BENCHMARK_TIMINGS | ConvertTo-Json -Compress | Set-Content -LiteralPath '__PROFILE_TIMING_FILE__' -Encoding UTF8
Remove-Variable __PROFILE_BENCHMARK_TIMINGS -Scope Global -ErrorAction SilentlyContinue
exit 0
"@
    $scenarios = @(
        [pscustomobject]@{ Name = 'Sem profile'; Script = "$quietPrefix exit 0" }
        [pscustomobject]@{ Name = 'Somente core'; Script = "$quietPrefix . $quotedCore; exit 0" }
        [pscustomobject]@{
            Name = 'Profile completo'
            Script = $fullProfileScript
        }
    )

    Write-Host "[profile] Benchmark: $Count amostra(s), $Warmup aquecimento(s) por cenario." -ForegroundColor Cyan
    Write-Host '[profile] Cada amostra inicia um novo processo pwsh; nenhuma rede e acessada.' -ForegroundColor DarkGray

    foreach ($scenario in $scenarios) {
        for ($i = 0; $i -lt $Warmup; $i++) {
            $null = Invoke-ProfileBenchmarkSample -FilePath $pwshPath -Script $scenario.Script
        }
    }

    $samples = @{}
    $blockSamples = @{}
    foreach ($scenario in $scenarios) { $samples[$scenario.Name] = @() }
    for ($i = 0; $i -lt $Count; $i++) {
        foreach ($scenario in $scenarios) {
            $sample = Invoke-ProfileBenchmarkSample -FilePath $pwshPath -Script $scenario.Script
            $samples[$scenario.Name] += $sample.TotalMs
            foreach ($timing in $sample.BlockTimings) {
                if (-not $blockSamples.ContainsKey($timing.Name)) { $blockSamples[$timing.Name] = @() }
                $blockSamples[$timing.Name] += [double]$timing.ElapsedMs
            }
        }
    }

    $baselineAverage = ($samples['Sem profile'] | Measure-Object -Average).Average
    $results = foreach ($scenario in $scenarios) {
        $values = [double[]]$samples[$scenario.Name]
        $measure = $values | Measure-Object -Average -Minimum -Maximum
        [pscustomobject]@{
            Cenario = $scenario.Name
            MediaMs = [Math]::Round($measure.Average, 1)
            MedianaMs = [Math]::Round((Get-ProfileMedian $values), 1)
            MinMs = [Math]::Round($measure.Minimum, 1)
            MaxMs = [Math]::Round($measure.Maximum, 1)
            OverheadMs = [Math]::Round(($measure.Average - $baselineAverage), 1)
            Amostras = $values.Count
        }
    }

    $blockOrder = @('Core', 'Oh My Posh', 'PSReadLine', 'CompletionPredictor', 'Terminal-Icons', 'posh-git', 'DockerCompletion', 'WinGet completion', 'zoxide', 'PSFzf', 'Extras')
    $blockResults = foreach ($blockName in $blockOrder) {
        if (-not $blockSamples.ContainsKey($blockName)) { continue }
        $values = [double[]]$blockSamples[$blockName]
        $measure = $values | Measure-Object -Average -Minimum -Maximum
        [pscustomobject]@{
            Bloco = $blockName
            MediaMs = [Math]::Round($measure.Average, 1)
            MedianaMs = [Math]::Round((Get-ProfileMedian $values), 1)
            MinMs = [Math]::Round($measure.Minimum, 1)
            MaxMs = [Math]::Round($measure.Maximum, 1)
            Amostras = $values.Count
        }
    }

    if ($PassThru) {
        return [pscustomobject]@{ Cenarios = @($results); Blocos = @($blockResults) }
    }
    $results | Format-Table -AutoSize | Out-Host
    Write-Host '[profile] OverheadMs e a diferenca media em relacao ao pwsh sem profile.' -ForegroundColor DarkGray
    Write-Host "`n[profile] Custo dos blocos no carregamento completo:" -ForegroundColor Cyan
    $blockResults | Format-Table -AutoSize | Out-Host
}

'@

$coreSyncBlock = if ($enableGistSync) {
@'
function New-ExtrasBackup {
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(1, 100)][int]$Retention = 10
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $backupDir = Join-Path (Split-Path -Path $Path -Parent) '.backups'
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $fileName = Split-Path -Path $Path -Leaf
    $backupPath = Join-Path $backupDir ("$fileName.bak_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force

    Get-ChildItem -LiteralPath $backupDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$fileName.bak_*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $Retention |
        Remove-Item -Force -ErrorAction SilentlyContinue

    return $backupPath
}

function Update-Extras {
    [CmdletBinding()]
    param(
        [switch]$Force,
        [switch]$Status
    )

    $configFile = $script:PROFILE_SYNC_FILE
    if (-not (Test-Path -LiteralPath $configFile)) {
        Write-Warning "[profile] Arquivo de sync nao encontrado: $configFile"
        return
    }

    try {
        $cfg = Get-Content -Raw -LiteralPath $configFile | ConvertFrom-Json -ErrorAction Stop
        if (-not $cfg.syncUrl -or -not $cfg.extrasFile) {
            throw 'gist-sync.json nao possui syncUrl ou extrasFile.'
        }

        $head = Invoke-WebRequest -Uri $cfg.syncUrl -Method HEAD -UseBasicParsing -ErrorAction Stop
        $remoteETag = [string]@($head.Headers['ETag'])[0]
        $remoteLastModified = [string]@($head.Headers['Last-Modified'])[0]
        $localETag = [string]@($cfg.etag)[0]
        $localLastModified = [string]@($cfg.lastModified)[0]
        $remoteTag = if ($remoteETag) { $remoteETag } else { $remoteLastModified }
        $localTag = if ($remoteETag) { $localETag } else { $localLastModified }

        if ($Status) {
            $state = if (-not $remoteTag) {
                'Indeterminado'
            } elseif ($remoteTag -eq $localTag) {
                'Atualizado'
            } else {
                'Atualizacao disponivel'
            }

            [pscustomobject]@{
                Status = $state
                URL = [string]$cfg.syncUrl
                Arquivo = [string]$cfg.extrasFile
                ETagLocal = $localETag
                ETagRemoto = $remoteETag
                LastModifiedRemoto = $remoteLastModified
                UltimaVerificacao = [string]$cfg.lastChecked
            }
            return
        }

        if (-not $Force -and $remoteTag -and $remoteTag -eq $localTag) {
            Write-Host "[profile] profile-extras.ps1 ja esta atualizado." -ForegroundColor DarkGray
            return
        }

        $extrasFile = [string]$cfg.extrasFile
        $extrasDir = Split-Path -Path $extrasFile -Parent
        if (-not (Test-Path -LiteralPath $extrasDir)) {
            New-Item -ItemType Directory -Path $extrasDir -Force | Out-Null
        }

        $temporaryFile = Join-Path $extrasDir ('.profile-extras.{0}.tmp' -f [guid]::NewGuid())
        $configTemporaryFile = "$configFile.tmp.$PID"
        try {
            Invoke-WebRequest -Uri $cfg.syncUrl -UseBasicParsing -OutFile $temporaryFile -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $temporaryFile) -or
                (Get-Item -LiteralPath $temporaryFile).Length -eq 0 -or
                [string]::IsNullOrWhiteSpace((Get-Content -Raw -LiteralPath $temporaryFile))) {
                throw 'O Gist retornou profile-extras.ps1 vazio.'
            }

            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $temporaryFile,
                [ref]$null,
                [ref]$parseErrors
            )
            if ($parseErrors.Count -gt 0) {
                $details = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
                throw "profile-extras.ps1 remoto possui sintaxe invalida: $details"
            }

            $backupPath = New-ExtrasBackup -Path $extrasFile -Retention 10
            Move-Item -LiteralPath $temporaryFile -Destination $extrasFile -Force

            $cfg.etag = $remoteETag
            $cfg.lastModified = $remoteLastModified
            $cfg.lastChecked = (Get-Date).ToString('o')
            $cfg | ConvertTo-Json | Set-Content -LiteralPath $configTemporaryFile -Encoding UTF8
            Move-Item -LiteralPath $configTemporaryFile -Destination $configFile -Force

            Write-Host "[profile] profile-extras.ps1 atualizado." -ForegroundColor Green
            if ($backupPath) {
                Write-Host "[profile] Backup: $backupPath" -ForegroundColor DarkGray
            }
            Write-Host "[profile] Recarregue com: . $PROFILE" -ForegroundColor DarkGray
        } finally {
            Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $configTemporaryFile -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning "[profile] Falha ao atualizar extras: $_"
    }
}

'@
} else {
@'
# Gist Sync manual desabilitado nesta instalacao.
'@
}

$predViewStyle = @("InlineView", "ListView", "InlineView")[$predChoice]
$predSource = @("History", "Plugin", "HistoryAndPlugin")[$srcChoice]
$tabHandler = if ($predChoice -eq 2) { "MenuComplete" } else { "Complete" }
$historySaveLine = if ($sharedHistory) {
    "        Set-PSReadLineOption -HistorySaveStyle SaveIncrementally"
} else {
    ""
}
$zoxideAliasLine = if ($zoxideAlias) {
    "    Set-Alias -Name cd -Value z -Option AllScope -Force"
} else {
    ""
}

$ohMyPoshBlock = if ($enableOhMyPosh) {
@"
`$__profileSessionLabel = 'local'
if (`$env:SSH_CONNECTION -or `$env:SSH_CLIENT) {
    `$__sshParts = @(`$env:SSH_CONNECTION -split '\s+')
    `$__sshTarget = if (`$__sshParts.Count -ge 3) { `$__sshParts[2] } else { `$null }
    `$__profileSessionLabel = if (`$__sshTarget) { "ssh+`$__sshTarget" } else { 'ssh' }
} elseif (`$env:CODESPACES -eq 'true' -or `$env:CODESPACE_NAME) {
    `$__profileSessionLabel = 'codespace'
} elseif (`$env:REMOTE_CONTAINERS -or `$env:REMOTE_CONTAINERS_IPC -or `$env:DEVCONTAINER) {
    `$__profileSessionLabel = 'devcontainer'
} elseif (`$env:KUBERNETES_SERVICE_HOST) {
    `$__profileSessionLabel = 'kubernetes'
} elseif (`$env:container -or (Test-Path -LiteralPath '/.dockerenv')) {
    `$__profileSessionLabel = 'container'
} elseif (`$env:WSL_DISTRO_NAME) {
    `$__profileSessionLabel = "wsl+`$env:WSL_DISTRO_NAME"
} elseif (`$env:SESSIONNAME -like 'RDP-*') {
    `$__profileSessionLabel = 'rdp'
} elseif (Get-Variable PSSenderInfo -ValueOnly -ErrorAction SilentlyContinue) {
    `$__profileSessionLabel = 'psremoting'
} elseif (`$env:USERNAME -eq 'WDAGUtilityAccount') {
    `$__profileSessionLabel = 'sandbox'
}
`$env:POSH_SESSION_LABEL = `$__profileSessionLabel
Remove-Variable __profileSessionLabel, __sshParts, __sshTarget -ErrorAction SilentlyContinue

`$__ompExe = "$escapedOmpExe"
if (-not `$__ompExe -or -not (Test-Path -LiteralPath `$__ompExe)) {
    `$__ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if (`$__ompCmd) { `$__ompExe = `$__ompCmd.Source }
}
if (-not `$__ompExe -or -not (Test-Path -LiteralPath `$__ompExe)) {
    foreach (`$candidate in @(
        "`$env:LOCALAPPDATA\Programs\oh-my-posh\bin\oh-my-posh.exe",
        "`$env:LOCALAPPDATA\oh-my-posh\oh-my-posh.exe",
        "`$env:LOCALAPPDATA\Microsoft\WindowsApps\oh-my-posh.exe",
        "`$env:ProgramFiles\oh-my-posh\bin\oh-my-posh.exe"
    )) {
        if (Test-Path -LiteralPath `$candidate) {
            `$__ompExe = `$candidate
            break
        }
    }
}

`$__themeFile = "$escapedOmpTheme"
if (-not `$__themeFile -or -not (Test-Path -LiteralPath `$__themeFile)) {
    `$__themesPath = if (`$env:POSH_THEMES_PATH -and (Test-Path -LiteralPath `$env:POSH_THEMES_PATH)) {
        `$env:POSH_THEMES_PATH
    } else {
        foreach (`$candidate in @(
            "`$env:LOCALAPPDATA\Programs\oh-my-posh\themes",
            "`$env:LOCALAPPDATA\oh-my-posh\themes",
            "`$env:ProgramFiles\oh-my-posh\themes"
        )) {
            if (Test-Path -LiteralPath `$candidate) {
                `$candidate
                break
            }
        }
    }
    if (`$__themesPath) { `$__themeFile = Join-Path `$__themesPath "paradox.omp.json" }
}

if (`$__ompExe -and `$__themeFile -and (Test-Path -LiteralPath `$__themeFile)) {
    & `$__ompExe init pwsh --config `$__themeFile | Invoke-Expression
} else {
    Write-Warning "[oh-my-posh] Executavel ou tema nao encontrado."
}

Remove-Variable __ompExe, __ompCmd, __themeFile, __themesPath -ErrorAction SilentlyContinue
"@
} else {
    "# Oh My Posh desabilitado nesta instalacao."
}

$psReadLineBlock = if ($configurePSReadLine) {
@"
if (Get-Module PSReadLine -ErrorAction SilentlyContinue) {
    try {
        Set-PSReadLineOption -PredictionSource $predSource
        Set-PSReadLineOption -PredictionViewStyle $predViewStyle
        Set-PSReadLineOption -EditMode Windows
        Set-PSReadLineOption -HistorySearchCursorMovesToEnd
$historySaveLine

        Set-PSReadLineKeyHandler -Key UpArrow    -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key DownArrow  -Function HistorySearchForward
        Set-PSReadLineKeyHandler -Key Tab        -Function $tabHandler
        Set-PSReadLineKeyHandler -Key Shift+Tab  -Function MenuComplete
        Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteCharOrExit
    } catch {
        Write-Warning "[PSReadLine] Configuracao interativa nao aplicada: `$_"
    }
}
"@
} else {
    "# PSReadLine desabilitado nesta instalacao."
}

$completionPredictorBlock = if ($installCompletion -and $usesPluginPrediction) {
@'
if (Test-ProfileModuleInstalled 'CompletionPredictor') {
    Import-Module CompletionPredictor -SkipEditionCheck -ErrorAction SilentlyContinue
}
'@
} else {
    "# CompletionPredictor desabilitado nesta instalacao."
}

$terminalIconsBlock = if ($installIcons) {
@'
if (Test-ProfileModuleInstalled 'Terminal-Icons') {
    function Get-ChildItem {
        Remove-Item Function:\Get-ChildItem -ErrorAction SilentlyContinue
        Import-Module Terminal-Icons -SkipEditionCheck -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Get-ChildItem @args
    }
}
'@
} else {
    "# Terminal-Icons desabilitado nesta instalacao."
}

$poshGitBlock = if ($enablePoshGit) {
@'
if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-ProfileModuleInstalled 'posh-git')) {
    function git {
        Remove-Item Function:\git -ErrorAction SilentlyContinue
        Import-Module posh-git -SkipEditionCheck -ErrorAction SilentlyContinue
        & (Get-Command git -CommandType Application) @args
    }
}
'@
} else {
    "# posh-git desabilitado nesta instalacao."
}

$dockerCompletionBlock = if ($installDocker) {
@'
if ((Get-Command docker -ErrorAction SilentlyContinue) -and (Test-ProfileModuleInstalled 'DockerCompletion')) {
    function docker {
        Remove-Item Function:\docker -ErrorAction SilentlyContinue
        Import-Module DockerCompletion -SkipEditionCheck -ErrorAction SilentlyContinue
        & (Get-Command docker -CommandType Application) @args
    }
}
'@
} else {
    "# DockerCompletion desabilitado nesta instalacao."
}

$wingetCompletionBlock = if ($installWinGet) {
@'
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [System.Text.Utf8Encoding]::new()
        $word = $wordToComplete.Replace('"', '""')
        $ast = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$word" --commandline "$ast" --position $cursorPosition |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
}
'@
} else {
    "# WinGet completion desabilitado nesta instalacao."
}

$zoxideBlock = if ($enableZoxide) {
@"
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    `$__zCache = "$escapedZoxideCache"
    if (-not (Test-Path -LiteralPath `$__zCache)) {
        rebuild-zoxide-cache -Quiet
    }
    if (Test-Path -LiteralPath `$__zCache) {
        . `$__zCache
    } else {
        Write-Warning '[zoxide] Cache indisponivel. Execute: rebuild-zoxide-cache'
    }
$zoxideAliasLine
    Remove-Variable __zCache -ErrorAction SilentlyContinue
}
"@
} else {
    "# Zoxide desabilitado nesta instalacao."
}

$psFzfBlock = if ($installFzf) {
@'
if ((Get-Command fzf -ErrorAction SilentlyContinue) -and (Test-ProfileModuleInstalled 'PSFzf')) {
    function Initialize-ProfilePSFzf {
        if (Get-Module PSFzf -ErrorAction SilentlyContinue) { return }

        try {
            Import-Module PSFzf -SkipEditionCheck -ErrorAction Stop
            Set-PsFzfOption -PSReadlineChordReverseHistory 'Ctrl+r' -PSReadlineChordProvider 'Ctrl+t'
        } catch {
            Write-Warning "[PSFzf] Falha ao carregar modulo: $_"
        }
    }

    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -BriefDescription 'PSFzfHistoryLazy' -ScriptBlock {
        Initialize-ProfilePSFzf
        if (Get-Command Invoke-FzfPsReadlineHandlerHistory -ErrorAction SilentlyContinue) {
            Invoke-FzfPsReadlineHandlerHistory
        }
    }
    Set-PSReadLineKeyHandler -Chord 'Ctrl+t' -BriefDescription 'PSFzfProviderLazy' -ScriptBlock {
        Initialize-ProfilePSFzf
        if (Get-Command Invoke-FzfPsReadlineHandlerProvider -ErrorAction SilentlyContinue) {
            Invoke-FzfPsReadlineHandlerProvider
        }
    }
}
'@
} else {
    "# PSFzf desabilitado nesta instalacao."
}

function Add-ProfileTimingWrapper {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][bool]$Enabled
    )

    if (-not $Enabled) { return $Content }
@"
`$__profileBlockTimer = Start-ProfileBlockTimer '$Name'
$Content
Stop-ProfileBlockTimer -Name '$Name' -Watch `$__profileBlockTimer
Remove-Variable __profileBlockTimer -ErrorAction SilentlyContinue
"@
}

$ohMyPoshBlock = Add-ProfileTimingWrapper 'Oh My Posh' $ohMyPoshBlock $enableOhMyPosh
$psReadLineBlock = Add-ProfileTimingWrapper 'PSReadLine' $psReadLineBlock $configurePSReadLine
$completionPredictorBlock = Add-ProfileTimingWrapper 'CompletionPredictor' $completionPredictorBlock $installCompletion
$terminalIconsBlock = Add-ProfileTimingWrapper 'Terminal-Icons' $terminalIconsBlock $installIcons
$poshGitBlock = Add-ProfileTimingWrapper 'posh-git' $poshGitBlock $enablePoshGit
$dockerCompletionBlock = Add-ProfileTimingWrapper 'DockerCompletion' $dockerCompletionBlock $installDocker
$wingetCompletionBlock = Add-ProfileTimingWrapper 'WinGet completion' $wingetCompletionBlock $installWinGet
$zoxideBlock = Add-ProfileTimingWrapper 'zoxide' $zoxideBlock $enableZoxide
$psFzfBlock = Add-ProfileTimingWrapper 'PSFzf' $psFzfBlock $installFzf

$mainProfile = @"
# ================================================================
#  PowerShell Profile - gerado por Install-PowerShellProfile.ps1
#  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# ================================================================

`$__profileCore = "$escapedCoreFile"
if (Test-Path -LiteralPath `$__profileCore) { . `$__profileCore }

`$__profileInteractiveSession =
    -not [System.Console]::IsInputRedirected -and
    -not [System.Console]::IsOutputRedirected -and
    -not [System.Environment]::GetEnvironmentVariable('CI') -and
    -not [System.Environment]::GetEnvironmentVariable('GITHUB_ACTIONS') -and
    -not [System.Environment]::GetEnvironmentVariable('SKIP_PWSH_PROFILE') -and
    -not [System.Environment]::GetEnvironmentVariable('POWERSHELL_PROFILE_LIGHT') -and
    (`$Host.Name -eq 'ConsoleHost' -or `$Host.Name -eq 'Visual Studio Code Host')

if (-not `$__profileInteractiveSession) {
    Remove-Variable __profileCore, __profileInteractiveSession -ErrorAction SilentlyContinue
    return
}

Remove-Variable __profileInteractiveSession -ErrorAction SilentlyContinue

`$__profileInteractive = "$escapedInteractiveFile"
`$__profileExtras = "$escapedExtrasFile"

if (Test-Path -LiteralPath `$__profileInteractive) { . `$__profileInteractive }
if (Test-Path -LiteralPath `$__profileExtras) { . `$__profileExtras }

Remove-Variable __profileCore, __profileInteractive, __profileExtras -ErrorAction SilentlyContinue
"@

$coreProfile = @"
# ================================================================
#  profile-core.ps1
#  Funcoes leves e comando manual de sync de extras.
# ================================================================

`$script:PROFILE_CONFIG_DIR = "$($ConfigDir.Replace('\', '\\'))"
`$script:PROFILE_SYNC_FILE = "$escapedSyncFile"

function Test-ProfileCommand {
    param([Parameter(Mandatory)][string]`$Name)
    return `$null -ne (Get-Command `$Name -ErrorAction SilentlyContinue)
}

function Test-ProfileModuleInstalled {
    param([Parameter(Mandatory)][string]`$Name)

    `$candidatePaths = [System.Collections.Generic.List[string]]::new()
    foreach (`$path in (`$env:PSModulePath -split ';')) {
        if (`$path) { `$candidatePaths.Add(`$path) }
    }

    `$oneDriveModules = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
    if (`$oneDriveModules -and -not `$candidatePaths.Contains(`$oneDriveModules)) {
        `$candidatePaths.Add(`$oneDriveModules)
    }

    foreach (`$path in `$candidatePaths) {
        if (Test-Path -LiteralPath (Join-Path `$path `$Name)) { return `$true }
    }
    return `$false
}

$coreZoxideBlock

$coreBenchmarkBlock
$coreSyncBlock
"@

$interactiveProfile = @"
# ================================================================
#  profile-interactive.ps1
#  Recursos visuais/interativos. Nao deve ser carregado por automacoes.
# ================================================================

$ohMyPoshBlock

$psReadLineBlock

$completionPredictorBlock

$terminalIconsBlock

$poshGitBlock

$dockerCompletionBlock

$wingetCompletionBlock

$zoxideBlock

$psFzfBlock
"@

$defaultExtras = @'
# ================================================================
#  profile-extras.ps1
#  Funcoes pessoais. Atualize manualmente com: update-extras
# ================================================================

function up {
    param([int]$n = 1)
    Set-Location ("../" * $n)
}

function ex { explorer.exe . }

function lsd { Get-ChildItem -Directory }

function lsl {
    Get-ChildItem | Sort-Object LastWriteTime -Descending |
        Format-Table Mode, LastWriteTime, @{
            Label = "Tamanho"; Expression = {
                if ($_.Length -gt 1MB) { "{0:N1} MB" -f ($_.Length / 1MB) }
                elseif ($_.Length -gt 1KB) { "{0:N1} KB" -f ($_.Length / 1KB) }
                else { "$($_.Length) B" }
            }; Align = "Right"
        }, Name
}

function gstat { git status -sb }

function gcommit {
    param([Parameter(Mandatory)][string]$Message)
    git add -A
    git commit -m $Message
}

function gpush { git push }

function glog {
    git log --oneline --graph --decorate --all | Select-Object -First 20
}

function git-clean {
    git branch --merged main | Where-Object { $_ -notmatch '^\*|main|master|develop' } |
        ForEach-Object { git branch -d $_.Trim() }
}

function timer {
    param([string]$Label = "Tempo")
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Read-Host "Pressione Enter para parar"
    $sw.Stop()
    Write-Host "$Label`: $($sw.Elapsed.ToString('hh\:mm\:ss\.fff'))" -ForegroundColor Cyan
}

function copy-file {
    param([Parameter(Mandatory)][string]$Path)
    Get-Content -LiteralPath $Path | Set-Clipboard
    Write-Host "Copiado: $Path" -ForegroundColor Green
}

function ff {
    param([Parameter(Mandatory)][string]$Name)
    Get-ChildItem -Recurse -Filter "*$Name*" -ErrorAction SilentlyContinue
}

function grep {
    param(
        [Parameter(Mandatory)][string]$Pattern,
        [string]$Path = "."
    )
    Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Select-String -Pattern $Pattern
}

function folder-size {
    param([string]$Path = ".")
    $size = (Get-ChildItem -LiteralPath $Path -Recurse -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    "{0:N2} MB ({1:N0} bytes)" -f ($size / 1MB), $size
}

function ping-test {
    param([string]$HostName = "8.8.8.8", [int]$Count = 4)
    Test-Connection $HostName -Count $Count | Format-Table Address, Latency, Status
}

function dl {
    param([Parameter(Mandatory)][string]$Url, [string]$Out = ".")
    $file = Split-Path $Url -Leaf
    Invoke-WebRequest -Uri $Url -OutFile (Join-Path $Out $file)
    Write-Host "Salvo: $file" -ForegroundColor Green
}

function myip { (Invoke-RestMethod "https://api.ipify.org?format=json").ip }

function dsh {
    param([Parameter(Mandatory)][string]$Name)
    $id = docker ps --filter "name=$Name" --format "{{.ID}}" | Select-Object -First 1
    if ($id) { docker exec -it $id sh } else { Write-Warning "Container nao encontrado: $Name" }
}

function reload { Start-Process pwsh; exit }

function gzip {
    $command = "git archive -v "
    foreach ($file in $args) {
        $command += "--add-file=$file "
    }
    $command += "-o ../git-archive.zip --format=zip HEAD"
    Invoke-Expression $command
}

function gchmod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$FileName,
        [Parameter(Position=1)]
        [string]$Chmod = "+x"
    )

    git config core.filemode false
    git update-index --chmod=$Chmod $FileName
}
'@

Write-Step "Criando backups"
New-Backup -Path $ProfilePath
New-Backup -Path $coreFile
New-Backup -Path $interactiveFile
New-Backup -Path $extrasFile
New-Backup -Path $syncFile
if ($customOmpThemeContent) { New-Backup -Path $customOmpTheme }

Write-Step "Gravando profile principal e arquivos modulares"
if ($PSCmdlet.ShouldProcess($ProfilePath, "Write PowerShell profile")) {
    Set-Content -LiteralPath $ProfilePath -Value $mainProfile -Encoding UTF8
    Set-Content -LiteralPath $coreFile -Value $coreProfile -Encoding UTF8
    Set-Content -LiteralPath $interactiveFile -Value $interactiveProfile -Encoding UTF8
    if ($customOmpThemeContent) {
        Set-Content -LiteralPath $customOmpTheme -Value $customOmpThemeContent -Encoding UTF8
    }
}

$etag = $null
$lastModified = $null
if ($downloadInitialExtras) {
    Write-Step "Baixando profile-extras inicial"
    try {
        $remoteExtras = Get-RemoteExtras -Url $ExtrasGistUrl
        Set-Content -LiteralPath $extrasFile -Value $remoteExtras.Content -Encoding UTF8
        $etag = $remoteExtras.ETag
        $lastModified = $remoteExtras.LastModified
        Write-Ok "profile-extras baixado do Gist"
    } catch {
        Write-Warn "Falha ao baixar extras do Gist. Usando extras padrao locais. Erro: $_"
        Set-Content -LiteralPath $extrasFile -Value $defaultExtras -Encoding UTF8
    }
} else {
    Write-Step "Criando profile-extras padrao local"
    Set-Content -LiteralPath $extrasFile -Value $defaultExtras -Encoding UTF8
}

if ($enableGistSync) {
    $syncConfig = [ordered]@{
        syncUrl = $ExtrasGistUrl
        etag = $etag
        lastModified = $lastModified
        lastChecked = (Get-Date).ToString('o')
        extrasFile = $extrasFile
    }

    Set-Content -LiteralPath $syncFile -Value ($syncConfig | ConvertTo-Json) -Encoding UTF8
} else {
    Write-Warn "Gist Sync manual desabilitado; gist-sync.json nao foi atualizado."
}

Write-Host ""
Write-Ok "Instalacao concluida."
Write-Host "Abra um novo terminal interativo ou rode: . `$PROFILE" -ForegroundColor Yellow
if ($enableGistSync) {
    Write-Host "Para atualizar extras manualmente: update-extras" -ForegroundColor Yellow
    Write-Host "Para consultar o estado sem baixar: update-extras -Status" -ForegroundColor DarkGray
}
Write-Host "Para pular o profile em automacoes: `$env:SKIP_PWSH_PROFILE='1'" -ForegroundColor DarkGray
