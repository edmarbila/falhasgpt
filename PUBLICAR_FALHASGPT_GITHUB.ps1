# Falhas GPT V5.1 — envio inicial e atualizacoes ao GitHub
# Origem: D:\Apps\FalhasGPT | Destino: edmarbila/falhasgpt | main
# Nao altera configuracoes do GitHub Pages, nem envia secrets.
[CmdletBinding()]
param([switch]$PularBuild)

$ErrorActionPreference = 'Stop'
$Projeto = 'D:\Apps\FalhasGPT'
$Repositorio = 'https://github.com/edmarbila/falhasgpt.git'

function Git([string[]]$Comando) {
    & git @Comando
    if ($LASTEXITCODE -ne 0) { throw "git $($Comando -join ' ') falhou (codigo $LASTEXITCODE)." }
}

Write-Host "=== FALHAS GPT: PUBLICACAO NO GITHUB ===" -ForegroundColor Cyan
foreach ($executavel in @('git', 'node', 'npm.cmd')) {
    if (-not (Get-Command $executavel -ErrorAction SilentlyContinue)) {
        throw "Comando nao encontrado: $executavel. Instale Git e Node.js 22+ antes de continuar."
    }
}
if (-not (Test-Path -LiteralPath $Projeto -PathType Container)) {
    throw "Pasta inexistente: $Projeto"
}
Set-Location -LiteralPath $Projeto
foreach ($item in @('README.md', 'package.json', 'build.mjs', 'public', 'sql', '.github')) {
    if (-not (Test-Path -LiteralPath $item)) {
        throw "Pacote incompleto: falta $item em $Projeto. Extraia primeiro a distribuicao V5.1 completa."
    }
}
if (-not (Test-Path '.github\workflows' -PathType Container)) {
    throw 'Nao encontrei .github\workflows. Confirme que o pacote inclui o workflow de Pages.'
}

# Impede que configuracao local e arquivos privados sejam preparados para commit.
$regras = @(
    '/public/project-config.js',
    '/.env', '/.env.*', '!/.env.example',
    '**/node_modules/', '/dist/',
    '**/.venv/', '**/__pycache__/',
    '*.session', '*.pem', '*.key', '*.p12', '*.pfx',
    '*.dump', '*.bak', '*.sql.gz'
)
$gitignore = Join-Path $Projeto '.gitignore'
$atuais = @()
if (Test-Path $gitignore) { $atuais = @(Get-Content -LiteralPath $gitignore) }
$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($regra in $regras) {
    if ($atuais -notcontains $regra) {
        [System.IO.File]::AppendAllText($gitignore, "`r`n$regra", $utf8)
    }
}

if (-not $PularBuild) {
    if (Test-Path -LiteralPath 'public\project-config.js') {
        Write-Host 'Testando build local (sem publicar dist)...' -ForegroundColor Yellow
        & npm.cmd run build:pages
        if ($LASTEXITCODE -ne 0) { throw 'Build local falhou. Corrija o erro antes do envio.' }
    } else {
        Write-Warning 'public/project-config.js ausente: build local ignorado. Configure as variaveis FGPT_SUPABASE_URL e FGPT_SUPABASE_PUBLIC_KEY no GitHub para o workflow.'
    }
}

if (-not (Test-Path -LiteralPath '.git' -PathType Container)) {
    Write-Host 'Preparando este diretorio para o primeiro commit...' -ForegroundColor Yellow
    Git -Comando @('init', '-b', 'main')
    Git -Comando @('remote', 'add', 'origin', $Repositorio)
    # O repositorio remoto ja tem um README. Trazer a historia sem sobrescrever os arquivos locais:
    Git -Comando @('fetch', 'origin', 'main')
    Git -Comando @('reset', '--mixed', 'origin/main')
} else {
    $remotos = @(& git remote)
    if ($remotos -notcontains 'origin') { Git -Comando @('remote', 'add', 'origin', $Repositorio) }
    $destinoAtual = (& git remote get-url origin).Trim()
    if (($destinoAtual -ne $Repositorio) -and ($destinoAtual -ne 'git@github.com:edmarbila/falhasgpt.git') -and ($destinoAtual -ne 'https://github.com/edmarbila/falhasgpt')) {
        throw "Remote origin diferente do esperado: $destinoAtual. Pare e confira antes de enviar."
    }
    $branch = (& git branch --show-current).Trim()
    if ($branch -ne 'main') { throw "A branch atual e '$branch'; use main ou resolva o estado do Git antes de publicar." }
    Git -Comando @('fetch', 'origin', 'main')
    & git merge-base --is-ancestor origin/main HEAD
    if ($LASTEXITCODE -ne 0) {
        throw 'Sua branch local nao contem a main remota. Sincronize e resolva eventuais conflitos antes de rodar o script novamente (git pull --rebase origin main).'
    }
}

Git -Comando @('add', '-A')
$nomes = @(& git diff --cached --name-only)
$bloqueados = @($nomes | Where-Object {
    $_ -match '(^|/)\.env(\.|$)' -or
    $_ -match '(^|/)project-config\.js$' -or
    $_ -match '(\.pem|\.key|\.p12|\.pfx|\.session|\.dump|\.bak)$'
})
if ($bloqueados.Count -gt 0) {
    Write-Host 'Arquivos sensiveis encontrados no staging:' -ForegroundColor Red
    $bloqueados | ForEach-Object { Write-Host " - $_" }
    throw 'Envio interrompido. Remova do indice com git rm --cached <arquivo> e inclua no .gitignore.'
}
Git -Comando @('diff', '--cached', '--check')
if ($nomes.Count -eq 0) {
    Write-Host 'Nenhuma alteracao para enviar.' -ForegroundColor Green
} else {
    Write-Host "Arquivos alterados/preparados: $($nomes.Count)" -ForegroundColor Cyan
    $nomes | ForEach-Object { Write-Host "  $_" }
    $confirma = Read-Host 'Confirma COMMIT e PUSH destes arquivos? Digite SIM'
    if ($confirma -cne 'SIM') {
        Write-Warning 'Operacao interrompida pelo usuario; os arquivos locais foram preservados.'
        exit 0
    }
    Git -Comando @('commit', '-m', 'Falhas GPT V5.1: atualizar projeto e arquivos de deploy')
}
Git -Comando @('push', '-u', 'origin', 'main')
Write-Host 'ENVIO CONCLUIDO. Consulte o repositorio e configure GitHub Pages > Source: GitHub Actions.' -ForegroundColor Green
Write-Host 'URL do repositorio: https://github.com/edmarbila/falhasgpt'
Write-Host 'URL prevista do site: https://edmarbila.github.io/falhasgpt/'
