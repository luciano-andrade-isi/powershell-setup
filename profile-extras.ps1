# Lista os comandos disponiveis no profile e suas finalidades
function info {
    $commands = [ordered]@{
        'profile-benchmark' = 'Core: mede o custo do profile. Exemplos: profile-benchmark; profile-benchmark -Count 10 -Warmup 2.'
        'update-extras'     = 'Core: atualiza os extras. Exemplos: update-extras; update-extras -Status.'
        up            = 'Sobe N niveis na arvore de diretorios. Exemplo: up 3.'
        ex            = 'Abre o diretorio atual no Explorer.'
        lsd           = 'Lista somente os diretorios da pasta atual.'
        lsl           = 'Lista arquivos por data com tamanhos legiveis.'
        gstatus       = 'Mostra o status resumido do repositorio Git.'
        gcommit       = 'Adiciona todas as alteracoes e cria um commit.'
        gpush         = 'Envia a branch e configura o upstream quando necessario.'
        glog          = 'Exibe os 20 commits mais recentes em formato grafico.'
        gclean        = 'Exclui branches locais ja mergeadas em main ou master.'
        timer         = 'Cronometra uma tarefa ate que Enter seja pressionado.'
        'copy-file'   = 'Copia o conteudo exato de um arquivo para o clipboard.'
        ff            = 'Localiza arquivos recursivamente por parte do nome.'
        grep          = 'Filtra texto do pipeline ou pesquisa arquivos. Exemplo: ps | grep pwsh.'
        'folder-size' = 'Calcula o tamanho total de uma pasta.'
        'ping-test'   = 'Executa um teste resumido de latencia e conectividade.'
        dl            = 'Baixa rapidamente um arquivo de uma URL.'
        myip          = 'Consulta o endereco IP publico atual.'
        dsh           = 'Abre um shell interativo em um container Docker.'
        reload        = 'Reinicia o PowerShell no mesmo terminal.'
        garchive      = 'Cria um ZIP do HEAD e inclui arquivos adicionais opcionais.'
        gchmod        = 'Altera o bit executavel de um arquivo no indice do Git.'
        mkcd          = 'Cria um diretorio e entra nele.'
        groot         = 'Navega para a raiz do repositorio Git atual.'
        gundo         = 'Desfaz o ultimo commit mantendo as alteracoes no stage.'
        ports         = 'Lista conexoes TCP locais e os processos responsaveis.'
        'kill-port'   = 'Encerra o processo que esta escutando em uma porta TCP.'
        extract       = 'Extrai arquivos ZIP, TAR, TAR.GZ, TGZ e GZIP.'
        'path-copy'   = 'Copia um caminho absoluto para o clipboard.'
        'json-format' = 'Formata JSON vindo de argumento, pipeline, arquivo ou clipboard.'
        trash         = 'Envia arquivos e diretorios para a Lixeira do Windows.'
        serve         = 'Inicia um servidor HTTP estatico usando Node.js.'
        info          = 'Lista os comandos fornecidos pelo profile-extras e os comandos essenciais do core.'
    }

    $nameWidth = ($commands.Keys | Measure-Object -Property Length -Maximum).Maximum
    foreach ($command in $commands.GetEnumerator()) {
        Write-Host ($command.Key.PadRight($nameWidth + 2)) -ForegroundColor Cyan -NoNewline
        Write-Host $command.Value -ForegroundColor DarkGray
    }
}

# Sobe N niveis de uma vez
function up {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 100)]
        [int]$Levels = 1
    )

    $path = (@('..') * $Levels) -join [System.IO.Path]::DirectorySeparatorChar
    Set-Location -LiteralPath $path
}
# up 3  ->  equivale a cd ../../..

# Abre o Explorer na pasta atual
function ex { Invoke-Item -LiteralPath (Get-Location).Path }

# Lista so diretorios
function lsd { Get-ChildItem -Directory }

# Lista arquivos e diretorios por data, com tamanho humano para arquivos
function lsl {
    Get-ChildItem | Sort-Object LastWriteTime -Descending |
        Format-Table Mode, LastWriteTime, @{
            Label = 'Tamanho'
            Expression = {
                if ($_.PSIsContainer) { return '' }
                if ($_.Length -ge 1GB) { return '{0:N1} GB' -f ($_.Length / 1GB) }
                if ($_.Length -ge 1MB) { return '{0:N1} MB' -f ($_.Length / 1MB) }
                if ($_.Length -ge 1KB) { return '{0:N1} KB' -f ($_.Length / 1KB) }
                return '{0:N0} B' -f $_.Length
            }
            Align = 'Right'
        }, Name
}

# Status resumido
function gstatus { git status --short --branch }

# Add + commit em um comando
function gcommit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    git add --all
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Falha ao adicionar os arquivos; o commit nao foi executado.'
        return
    }

    git commit --message $Message
}

# Push com upstream automatico quando necessario
function gpush {
    $branch = git branch --show-current
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
        Write-Error 'Nao foi possivel determinar a branch atual (HEAD pode estar destacado).'
        return
    }

    git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        git push
    }
    else {
        git push --set-upstream origin $branch
    }
}

# Log visual compacto
function glog {
    git log --oneline --graph --decorate --all --max-count=20
}

# Limpa branches locais ja mergeadas em main/master
function gclean {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$BaseBranch
    )

    if (-not $BaseBranch) {
        foreach ($candidate in 'main', 'master') {
            git show-ref --verify --quiet "refs/heads/$candidate"
            if ($LASTEXITCODE -eq 0) {
                $BaseBranch = $candidate
                break
            }
        }
    }

    if (-not $BaseBranch) {
        Write-Error 'Informe -BaseBranch; nenhuma branch local main/master foi encontrada.'
        return
    }

    $protectedBranches = @('main', 'master', 'develop', $BaseBranch)
    $mergedBranches = git for-each-ref --format='%(refname:short)' --merged $BaseBranch refs/heads/
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Falha ao listar branches mergeadas em '$BaseBranch'."
        return
    }

    foreach ($branch in $mergedBranches) {
        if ($branch -and $branch -notin $protectedBranches) {
            if ($PSCmdlet.ShouldProcess($branch, "Excluir branch local mergeada em $BaseBranch")) {
                git branch --delete -- $branch
            }
        }
    }
}

# Cronometro simples
function timer {
    param([string]$Label = 'Tempo')

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Read-Host 'Pressione Enter para parar'
    $stopwatch.Stop()
    Write-Host "$Label`: $($stopwatch.Elapsed.ToString('hh\:mm\:ss\.fff'))" -ForegroundColor Cyan
}

# Copia o conteudo exato de um arquivo para o clipboard
function copy-file {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    [System.IO.File]::ReadAllText($resolvedPath) | Set-Clipboard
    Write-Host "Copiado: $resolvedPath" -ForegroundColor Green
}

# Encontra arquivos por nome (recursivo)
function ff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [string]$Path = '.'
    )

    Get-ChildItem -LiteralPath $Path -Recurse -File -Filter "*$Name*" -ErrorAction SilentlyContinue
}

# Filtra a saida do pipeline ou pesquisa recursivamente em arquivos
function grep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Pattern,

        [Parameter(Position = 1)]
        [string]$Path = '.',

        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [psobject]$InputObject,

        [Alias('F')]
        [switch]$SimpleMatch,

        [switch]$CaseSensitive,

        [Alias('v')]
        [switch]$NotMatch,

        [int[]]$Context
    )

    begin {
        $expectsPipelineInput = $MyInvocation.ExpectingInput
        $pipelineItems = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($expectsPipelineInput) {
            $pipelineItems.Add($InputObject)
        }
    }
    end {
        $searchParameters = @{
            Pattern       = $Pattern
            SimpleMatch   = $SimpleMatch
            CaseSensitive = $CaseSensitive
            NotMatch      = $NotMatch
        }
        if ($PSBoundParameters.ContainsKey('Context')) {
            $searchParameters.Context = $Context
        }

        if ($expectsPipelineInput) {
            $pipelineItems |
                Out-String -Stream -Width 4096 |
                Select-String @searchParameters
            return
        }

        Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
            Select-String @searchParameters
    }
}

# Calcula o tamanho total de uma pasta
function folder-size {
    [CmdletBinding()]
    param([string]$Path = '.')

    $size = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum |
        Select-Object -ExpandProperty Sum

    if ($null -eq $size) { $size = 0 }
    '{0:N2} MB ({1:N0} bytes)' -f ($size / 1MB), $size
}

# Teste de latencia resumido
function ping-test {
    [CmdletBinding()]
    param(
        [Alias('Address')]
        [string]$TargetName = '8.8.8.8',

        [ValidateRange(1, 100)]
        [int]$Count = 4
    )

    Test-Connection -TargetName $TargetName -Count $Count |
        Format-Table Address, Latency, Status
}

# Download rapido de arquivo
function dl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uri]$Url,

        [string]$Out = '.',

        [string]$FileName
    )

    if (-not $FileName) {
        $FileName = [uri]::UnescapeDataString([System.IO.Path]::GetFileName($Url.AbsolutePath))
    }
    if ([string]::IsNullOrWhiteSpace($FileName)) {
        Write-Error 'A URL nao contem um nome de arquivo; informe -FileName.'
        return
    }

    $destinationDirectory = (Resolve-Path -LiteralPath $Out -ErrorAction Stop).Path
    $destination = Join-Path $destinationDirectory $FileName
    Invoke-WebRequest -Uri $Url -OutFile $destination -ErrorAction Stop
    Write-Host "Salvo: $destination" -ForegroundColor Green
}

# IP publico atual
function myip { (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json').ip }

# Shell interativo no container pelo nome parcial
function dsh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [string]$Shell = 'sh'
    )

    $id = docker ps --filter "name=$Name" --format '{{.ID}}' | Select-Object -First 1
    if ($id) {
        docker exec --interactive --tty $id $Shell
    }
    else {
        Write-Warning "Container nao encontrado: $Name"
    }
}

# Reinicia o PowerShell no mesmo terminal
function reload {
    $pwshPath = (Get-Process -Id $PID).Path
    & $pwshPath -NoLogo
    exit
}

# Cria um ZIP do HEAD e, opcionalmente, inclui arquivos adicionais
function garchive {
    [CmdletBinding()]
    param(
        [string[]]$AdditionalFile,

        [string]$OutputPath = (Join-Path '..' 'git-archive.zip')
    )

    $archiveArguments = @('archive', '--verbose', '--format=zip', "--output=$OutputPath")
    foreach ($file in $AdditionalFile) {
        $archiveArguments += "--add-file=$file"
    }
    $archiveArguments += 'HEAD'

    & git @archiveArguments
}

# Altera o bit executavel no indice do Git
function gchmod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$FileName,

        [Parameter(Position = 1)]
        [ValidateSet('+x', '-x')]
        [string]$Mode = '+x'
    )

    git update-index "--chmod=$Mode" -- $FileName
}

# Cria um diretorio e entra nele
function mkcd {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $directory = New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop
    Set-Location -LiteralPath $directory.FullName
}

# Navega para a raiz do repositorio Git atual
function groot {
    $root = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) {
        Write-Error 'O diretorio atual nao pertence a um repositorio Git.'
        return
    }

    Set-Location -LiteralPath $root
}

# Desfaz o ultimo commit e mantem as alteracoes no stage
function gundo {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param()

    git rev-parse --verify --quiet 'HEAD~1'
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Nao existe um commit anterior para restaurar.'
        return
    }

    if ($PSCmdlet.ShouldProcess('HEAD', 'Executar git reset --soft HEAD~1')) {
        git reset --soft 'HEAD~1'
    }
}

# Lista conexoes TCP locais e os processos responsaveis
function ports {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 65535)]
        [int]$Port
    )

    $parameters = @{ ErrorAction = 'SilentlyContinue' }
    if ($PSBoundParameters.ContainsKey('Port')) {
        $parameters.LocalPort = $Port
    }

    $processNames = @{}
    Get-NetTCPConnection @parameters |
        Sort-Object LocalPort, State, OwningProcess |
        Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State,
            @{ Name = 'ProcessId'; Expression = { $_.OwningProcess } },
            @{ Name = 'ProcessName'; Expression = {
                $processId = $_.OwningProcess
                if (-not $processNames.ContainsKey($processId)) {
                    $processNames[$processId] = (Get-Process -Id $processId -ErrorAction SilentlyContinue).ProcessName
                }
                $processNames[$processId]
            } }
}

# Encerra o processo que esta escutando em uma porta TCP
function kill-port {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateRange(1, 65535)]
        [int]$Port
    )

    $processIds = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique

    if (-not $processIds) {
        Write-Warning "Nenhum processo esta escutando na porta $Port."
        return
    }

    foreach ($processId in $processIds) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        $description = if ($process) { "$($process.ProcessName) (PID $processId)" } else { "PID $processId" }
        if ($PSCmdlet.ShouldProcess($description, "Encerrar processo que ocupa a porta $Port")) {
            Stop-Process -Id $processId -ErrorAction Stop
        }
    }
}

# Extrai arquivos ZIP, TAR, TAR.GZ, TGZ e GZIP
function extract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [string]$Destination,

        [switch]$Force
    )

    $source = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $sourceName = [System.IO.Path]::GetFileName($source)
    $isPlainGzip = $sourceName -match '(?i)\.gz$' -and $sourceName -notmatch '(?i)\.tar\.gz$'

    if (-not $Destination) {
        $parent = Split-Path -Parent $source
        if ($isPlainGzip) {
            $Destination = $parent
        }
        else {
            $archiveName = $sourceName -replace '(?i)\.(tar\.gz|tgz|zip|tar)$', ''
            $Destination = Join-Path $parent $archiveName
        }
    }

    $destinationDirectory = New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop

    if ($sourceName -match '(?i)\.zip$') {
        Expand-Archive -LiteralPath $source -DestinationPath $destinationDirectory.FullName -Force:$Force
        return
    }

    if ($sourceName -match '(?i)\.(tar|tar\.gz|tgz)$') {
        tar --extract --file $source --directory $destinationDirectory.FullName
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Falha ao extrair '$sourceName' com tar."
        }
        return
    }

    if ($isPlainGzip) {
        $outputName = [System.IO.Path]::GetFileNameWithoutExtension($sourceName)
        $outputPath = Join-Path $destinationDirectory.FullName $outputName
        if ((Test-Path -LiteralPath $outputPath) -and -not $Force) {
            Write-Error "O arquivo de destino ja existe: $outputPath. Use -Force para sobrescrever."
            return
        }

        $inputStream = [System.IO.File]::OpenRead($source)
        try {
            $gzipStream = [System.IO.Compression.GZipStream]::new(
                $inputStream,
                [System.IO.Compression.CompressionMode]::Decompress
            )
            try {
                $outputStream = [System.IO.File]::Create($outputPath)
                try {
                    $gzipStream.CopyTo($outputStream)
                }
                finally {
                    $outputStream.Dispose()
                }
            }
            finally {
                $gzipStream.Dispose()
            }
        }
        finally {
            $inputStream.Dispose()
        }
        return Get-Item -LiteralPath $outputPath
    }

    Write-Error "Formato nao suportado: $sourceName"
}

# Copia um caminho absoluto para o clipboard
function path-copy {
    [CmdletBinding()]
    param([string]$Path = '.')

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    Set-Clipboard -Value $resolvedPath
    Write-Host "Caminho copiado: $resolvedPath" -ForegroundColor Green
}

# Formata JSON recebido por argumento, pipeline, arquivo ou clipboard
function json-format {
    [CmdletBinding(DefaultParameterSetName = 'Input')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ParameterSetName = 'Input')]
        [AllowEmptyString()]
        [string]$InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Clipboard')]
        [switch]$FromClipboard,

        [ValidateRange(1, 100)]
        [int]$Depth = 20
    )

    begin {
        $jsonBuilder = [System.Text.StringBuilder]::new()
    }
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Input' -and $null -ne $InputObject) {
            $null = $jsonBuilder.AppendLine($InputObject)
        }
    }
    end {
        $json = switch ($PSCmdlet.ParameterSetName) {
            'Path' { Get-Content -LiteralPath $Path -Raw -ErrorAction Stop }
            'Clipboard' { Get-Clipboard -Raw }
            default { $jsonBuilder.ToString() }
        }

        if ([string]::IsNullOrWhiteSpace($json)) {
            Write-Error 'Nenhum JSON foi informado.'
            return
        }

        $json | ConvertFrom-Json -ErrorAction Stop | ConvertTo-Json -Depth $Depth
    }
}

# Envia arquivos e diretorios para a Lixeira do Windows
function trash {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string[]]$Path
    )

    process {
        foreach ($itemPath in $Path) {
            $item = Get-Item -LiteralPath $itemPath -Force -ErrorAction Stop
            if (-not $PSCmdlet.ShouldProcess($item.FullName, 'Enviar para a Lixeira')) {
                continue
            }

            if ($item.PSIsContainer) {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                    $item.FullName,
                    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                )
            }
            else {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                    $item.FullName,
                    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                )
            }
        }
    }
}

# Inicia um servidor HTTP estatico no diretorio informado usando Node.js
function serve {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 65535)]
        [int]$Port = 8000,

        [string]$Path = '.',

        [string]$Bind = '127.0.0.1'
    )

    $directory = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue
    if (-not $node) {
        Write-Error 'Node.js nao foi encontrado no PATH.'
        return
    }

    $serverScript = @'
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(process.argv[1]);
const port = Number(process.argv[2]);
const host = process.argv[3];
const contentTypes = {
  '.css': 'text/css; charset=utf-8',
  '.gif': 'image/gif',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.jpeg': 'image/jpeg',
  '.jpg': 'image/jpeg',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.wasm': 'application/wasm',
  '.xml': 'application/xml; charset=utf-8'
};

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  })[character]);
}

function send(response, statusCode, body, contentType = 'text/plain; charset=utf-8') {
  response.writeHead(statusCode, {
    'Content-Type': contentType,
    'Content-Length': Buffer.byteLength(body),
    'X-Content-Type-Options': 'nosniff'
  });
  response.end(body);
}

async function sendFile(request, response, filePath, stats) {
  response.writeHead(200, {
    'Content-Type': contentTypes[path.extname(filePath).toLowerCase()] || 'application/octet-stream',
    'Content-Length': stats.size,
    'X-Content-Type-Options': 'nosniff'
  });
  if (request.method === 'HEAD') {
    response.end();
    return;
  }
  fs.createReadStream(filePath).on('error', () => response.destroy()).pipe(response);
}

async function sendDirectory(response, directoryPath, requestPath) {
  const entries = await fs.promises.readdir(directoryPath, { withFileTypes: true });
  const basePath = requestPath.endsWith('/') ? requestPath : `${requestPath}/`;
  const links = entries
    .sort((left, right) => left.name.localeCompare(right.name))
    .map(entry => {
      const suffix = entry.isDirectory() ? '/' : '';
      const href = `${basePath}${encodeURIComponent(entry.name)}${suffix}`;
      return `<li><a href="${href}">${escapeHtml(entry.name)}${suffix}</a></li>`;
    })
    .join('\n');
  const parent = requestPath === '/' ? '' : '<li><a href="../">../</a></li>';
  const body = `<!doctype html><meta charset="utf-8"><title>Index of ${escapeHtml(requestPath)}</title>` +
    `<h1>Index of ${escapeHtml(requestPath)}</h1><ul>${parent}${links}</ul>`;
  send(response, 200, body, 'text/html; charset=utf-8');
}

const server = http.createServer(async (request, response) => {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    response.setHeader('Allow', 'GET, HEAD');
    send(response, 405, 'Method Not Allowed');
    return;
  }

  try {
    const requestPath = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    const filePath = path.resolve(root, requestPath.replace(/^\/+/, ''));
    if (filePath !== root && !filePath.startsWith(`${root}${path.sep}`)) {
      send(response, 403, 'Forbidden');
      return;
    }

    const stats = await fs.promises.stat(filePath);
    if (stats.isDirectory()) {
      const indexPath = path.join(filePath, 'index.html');
      try {
        const indexStats = await fs.promises.stat(indexPath);
        await sendFile(request, response, indexPath, indexStats);
      } catch {
        await sendDirectory(response, filePath, requestPath);
      }
      return;
    }

    if (!stats.isFile()) {
      send(response, 404, 'Not Found');
      return;
    }
    await sendFile(request, response, filePath, stats);
  } catch (error) {
    send(response, error.code === 'EACCES' ? 403 : 404, error.code === 'EACCES' ? 'Forbidden' : 'Not Found');
  }
});

server.listen(port, host);
'@

    Write-Host "Servidor em http://$Bind`:$Port/ (Ctrl+C para encerrar)" -ForegroundColor Cyan
    & $node.Source -e $serverScript $directory $Port $Bind
}
