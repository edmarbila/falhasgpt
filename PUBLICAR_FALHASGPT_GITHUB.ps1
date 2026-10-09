# Falhas GPT - Publicar e atualizar no GitHub (v3: corrige histories independentes)
# Diretorio local: D:\Apps\FalhasGPT
# Branch remota: edmarbila/falhasgpt (main)
# Executar: powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\Apps\FalhasGPT\PUBLICAR_FALHASGPT_GITHUB.ps1"
# Opcional: -PularBuild

[CmdletBinding()]
param([switch]$PularBuild)

$ErrorActionPreference = 'Stop'
$Projeto = 'D:\Apps\FalhasGPT'
$Repositorio = 'https://github.com/edmarbila/falhasgpt.git'
$BranchAlvo = 'main'

# Nao criar funcao "Git" (conflita com git.exe no PowerShell).
function Invoke-GitChecked {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    & git.exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Falhou: git $($Arguments -join ' ') (codigo $LASTEXITCODE)."
    }
}
function Test-GitOk {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    & git.exe @Arguments *> $null
    return ($LASTEXITCODE -eq 0)
}

Write-Host '=== FALHAS GPT - ENVIO SEGURO PARA GITHUB ===' -ForegroundColor Cyan
foreach ($exec in @('git.exe','node.exe','npm.cmd')) {
    if (-not (Get-Command $exec -ErrorAction SilentlyContinue)) {
        throw "Comando nao encontrado: $exec. Instale ou configure no PATH."
    }
}
if (-not (Test-Path -LiteralPath $Projeto -PathType Container)) {
    throw "Pasta nao encontrada: $Projeto"
}
Set-Location -LiteralPath $Projeto
foreach ($item in @('README.md','package.json','build.mjs','public','sql','.github')) {
    if (-not (Test-Path -LiteralPath $item)) {
        throw "Falta o arquivo/pasta $item na distribuicao V5.1."
    }
}
if (-not (Test-Path -LiteralPath '.github\workflows' -PathType Container)) {
    throw 'Nao foi encontrado o workflow em .github\workflows.'
}

# Acrescenta regras de protecao; nao sobrescreve o .gitignore existente.
$regras = @(
    '/public/project-config.js',
    '/.env', '/.env.*', '!/.env.example',
    '**/node_modules/', '/dist/',
    '**/.venv/', '**/__pycache__/',
    '*.session', '*.session-journal', '*.pem', '*.key', '*.p12', '*.pfx',
    '*.dump', '*.bak', '*.sql.gz'
)
$arquivoIgnore = Join-Path $Projeto '.gitignore'
$regrasAtuais = @()
if (Test-Path -LiteralPath $arquivoIgnore) {
    $regrasAtuais = @(Get-Content -LiteralPath $arquivoIgnore)
}
$utf8SemBom = New-Object System.Text.UTF8Encoding($false)
foreach ($regra in $regras) {
    if ($regrasAtuais -notcontains $regra) {
        [System.IO.File]::AppendAllText($arquivoIgnore, "`r`n$regra", $utf8SemBom)
        $regrasAtuais += $regra
    }
}

if (-not $PularBuild) {
    if (Test-Path -LiteralPath 'public\project-config.js' -PathType Leaf) {
        Write-Host 'Validando build local...' -ForegroundColor Yellow
        & npm.cmd run build:pages
        if ($LASTEXITCODE -ne 0) { throw 'Build falhou; envio interrompido.' }
    } else {
        Write-Warning 'Sem project-config.js local: build pulado. Configure as variaveis de deploy do GitHub Actions.'
    }
}

if (-not (Test-Path -LiteralPath '.git')) {
    Write-Host 'Inicializando repositorio local na main...' -ForegroundColor Yellow
    Invoke-GitChecked -Arguments @('init','-b',$BranchAlvo)
}
if (-not (Test-GitOk -Arguments @('rev-parse','--is-inside-work-tree'))) {
    throw 'O Git nao reconheceu o diretorio como repositorio.'
}
$raiz = (& git.exe rev-parse --show-toplevel | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel consultar a raiz do Git.' }
if ([IO.Path]::GetFullPath($raiz).TrimEnd('\') -ine [IO.Path]::GetFullPath($Projeto).TrimEnd('\')) {
    throw "O repositorio Git pertence a outra pasta: $raiz. Envio interrompido."
}

$remotos = @(& git.exe remote)
if ($LASTEXITCODE -ne 0) { throw 'Falha ao listar remotos.' }
if ($remotos -notcontains 'origin') {
    Invoke-GitChecked -Arguments @('remote','add','origin',$Repositorio)
}
$origin = (& git.exe remote get-url origin | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar origin.' }
if ($origin -notin @($Repositorio,'https://github.com/edmarbila/falhasgpt','git@github.com:edmarbila/falhasgpt.git')) {
    throw "O remote origin nao e o esperado: $origin"
}

$branch = (& git.exe branch --show-current | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Falha ao identificar a branch local.' }
if ($branch -eq 'master') {
    if (Test-GitOk -Arguments @('show-ref','--verify','refs/heads/main')) {
        throw 'As branches locais main e master coexistem. Verifique antes de prosseguir.'
    }
    Write-Host 'Renomeando automaticamente master para main...' -ForegroundColor Yellow
    Invoke-GitChecked -Arguments @('branch','-m','master','main')
    $branch = 'main'
}
if ($branch -ne 'main') {
    throw "Branch local '$branch' diferente de main. Volte para main antes de publicar."
}

Write-Host 'Buscando o historico ja existente no GitHub...' -ForegroundColor Yellow
Invoke-GitChecked -Arguments @('fetch','origin','main')
$temHead = Test-GitOk -Arguments @('rev-parse','--verify','HEAD')
$temRemote = Test-GitOk -Arguments @('show-ref','--verify','refs/remotes/origin/main')
if (-not $temRemote) { throw 'A branch origin/main nao foi encontrada apos fetch.' }

# Caso repositorio local ainda nao tenha primeiro commit, usar o remoto
# como ponto de partida sem apagar arquivos de trabalho locais.
if (-not $temHead) {
    Write-Host 'Aproveitando o commit README.md que ja existe no GitHub...' -ForegroundColor Yellow
    Invoke-GitChecked -Arguments @('reset','--mixed','origin/main')
}

# Inspeciona todos os arquivos monitorados, inclusive aqueles ja presentes
# em commits anteriores. Arquivos sensiveis nao devem ir ao GitHub.
Invoke-GitChecked -Arguments @('add','-A')
$monitorados = @(& git.exe ls-files)
if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel listar arquivos do Git.' }
$proibidos = @($monitorados | Where-Object {
    $_ -match '(^|/)project-config\.js$' -or
    $_ -match '(^|/)\.env($|\.)' -and $_ -notmatch '(^|/)\.env\.example$' -or
    $_ -match '(^|/)dist/' -or
    $_ -match '(^|/)node_modules/' -or
    $_ -match '(\.pem|\.key|\.p12|\.pfx|\.session|\.session-journal|\.dump|\.bak|\.sql\.gz)$'
})
if ($proibidos.Count -gt 0) {
    $proibidos | ForEach-Object { Write-Host "BLOQUEADO: $_" -ForegroundColor Red }
    throw 'Arquivos privados ou de build estao rastreados pelo Git. Retire do indice/historico antes de publicar.'
}

$pendentes = @(& git.exe diff --cached --name-only)
if ($LASTEXITCODE -ne 0) { throw 'Falha ao inspecionar o staging.' }
if ($pendentes.Count -gt 0) {
    Write-Host "Arquivos preparados para commit: $($pendentes.Count)" -ForegroundColor Cyan
    $pendentes | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host 'Sem novos arquivos locais para commit.' -ForegroundColor Cyan
}
Write-Host ''
Write-Host 'O script tambem vai integrar o commit remoto README.md (sem usar push --force).' -ForegroundColor Yellow
$confirma = Read-Host 'Para continuar com COMMIT / SINCRONIZACAO / PUSH, digite SIM'
if ($confirma -cne 'SIM') {
    Write-Warning 'Cancelado. Nada foi publicado.'
    exit 0
}

if ($pendentes.Count -gt 0) {
    Invoke-GitChecked -Arguments @('commit','-m','Falhas GPT V5.1: projeto completo e deploy automatico')
}

# O primeiro clone local pode ter sido inicializado com um commit independente
# do README inicial no GitHub. Resolver sem --force e sem perder os commits.
$remoteEhAncestral = Test-GitOk -Arguments @('merge-base','--is-ancestor','origin/main','HEAD')
if (-not $remoteEhAncestral) {
    $historiaEmComum = Test-GitOk -Arguments @('merge-base','HEAD','origin/main')
    if (-not $historiaEmComum) {
        $arquivosRemotos = @(& git.exe ls-tree -r --name-only origin/main)
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao inspecionar arquivos remotos.' }
        if ($arquivosRemotos.Count -ne 1 -or $arquivosRemotos[0] -ne 'README.md') {
            throw 'O GitHub tem arquivos alem do README e historicos distintos. Sincronizacao automatica interrompida para nao sobrescrever dados.'
        }
        Write-Host 'Integrando os dois commits iniciais independentes (remoto contem apenas README.md)...' -ForegroundColor Yellow
        # A arvore do projeto local prevalece. O commit remoto vira ancestral,
        # preservando o historico e permitindo push normal, sem --force.
        Invoke-GitChecked -Arguments @('merge','--allow-unrelated-histories','-s','ours','--no-edit','origin/main')
    } else {
        Write-Host 'Ha atualizacoes remotas: tentando merge normal e seguro...' -ForegroundColor Yellow
        & git.exe merge --no-edit origin/main
        if ($LASTEXITCODE -ne 0) {
            if (Test-Path -LiteralPath '.git\MERGE_HEAD') {
                & git.exe merge --abort | Out-Null
            }
            throw 'Conflito com alteracoes do GitHub. Merge cancelado; arquivos locais preservados. Resolva antes de publicar.'
        }
    }
}

Write-Host 'Enviando main para origin/main (sem forcar historico)...' -ForegroundColor Yellow
Invoke-GitChecked -Arguments @('push','-u','origin','main')
Write-Host ''
Write-Host 'ENVIO CONCLUIDO!' -ForegroundColor Green
Write-Host 'Repositorio: https://github.com/edmarbila/falhasgpt'
Write-Host 'Pages, quando habilitado: https://edmarbila.github.io/falhasgpt/'
