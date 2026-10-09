# Atualizar, diagnosticar e preservar a configuração

## Código do site versus dados

Cadastro de procedimento, tópico, RE e PDF é salvo no Supabase; não exige deploy. Alterações de interface, JavaScript, configuração central ou assets exigem atualizar os arquivos e fazer deploy. Migração SQL é outra operação: enviar SQL ao Git não o aplica ao banco.

Antes de substituir um projeto local, faça uma cópia da pasta e preserve `public/project-config.js`. Os pacotes de distribuição vêm com conexão vazia. Se usar variáveis no provedor, mantenha os valores lá e confira se o novo deploy utiliza o mesmo projeto Supabase.

Para um repositório já criado:

```powershell
cd "D:\Apps\FalhasGPT"
git status
git pull --ff-only origin main
```

Faça o pull com a pasta limpa. Se houver alterações suas ou divergência, não use `--force`: preserve o trabalho e resolva o conflito antes. Copie somente os novos arquivos do projeto, mantendo sua configuração e o diretório `.git`. Depois:

```powershell
npm.cmd run build:pages
git diff --stat
git add .
git diff --cached --stat
git commit -m "Atualiza Falhas GPT"
git push origin main
```

Os comandos pressupõem branch `main`. Em outro nome de branch, ajuste o provedor e o workflow. Não mude o endereço `origin` de um projeto existente sem conferir com `git remote -v`.

## Retornar a uma versão de interface

Guarde o commit de uma versão aprovada. Se um deploy de interface falhar, use o rollback do provedor ou faça `git revert` do commit problemático e envie novamente. Não use um instalador SQL antigo como rollback do banco. Mudanças de banco exigem backup e uma migração própria.

## Diagnóstico

| Sintoma | Conferir |
| --- | --- |
| Configuração aparece para cada pessoa | Arquivo `project-config.js` preenchido no build final, ou as duas variáveis e novo deploy; configurar só no navegador é local |
| Página sem estilo / assets 404 | Upload de `dist` completo, caminho de saída e subpasta; não misture arquivos de pacotes antigos |
| Worker PDF não carrega | Publique `vendor/pdfjs` completo e sirva `.mjs` como JavaScript; no Cloudflare, preserve `_headers` |
| Build reclama de conexão ausente | Preencha o arquivo ou as duas variáveis; `build:pages` exige conexão válida |
| Login funciona em um lugar e falha em outro | Compare o projeto Supabase configurado e a confirmação de e-mail; bancos diferentes não compartilham contas |
| Administrador não aparece | Confira UUID no projeto correto e registro ativo na validação SQL; o UUID muda em projeto novo |
| Cadastro falha com RE liberado | RE pode estar vinculado, revogado, malformatado, conta já existente ou Auth/SMTP recusando; guarde erro e logs do Supabase |
| Confirmação abre URL errada | Site URL, Redirect URLs com subpasta/barra e template de e-mail |
| Nenhum procedimento aparece | Registro pode estar como rascunho, excluído, em outro Supabase ou acesso sem RE ativo |
| RPC não encontrada | Migrações aplicadas no projeto certo, schema `public` exposto e recarga do schema; o SQL já envia `NOTIFY pgrst` |
| `permission denied to set parameter pg_trgm...` | Use o SQL V5 corrigido deste pacote, sem SET de parâmetros da extensão |
| `Já existe um acervo Falhas GPT` | Você escolheu o instalador novo para uma base existente; use a rota de atualização/validação |
| GitHub Actions marcado como skipped | `FGPT_ENABLE_GITHUB_PAGES` não está `true`; isso é esperado quando usa somente Cloudflare |
| SQL ou busca demoram em acervo grande | Guarde a consulta, quantidade de documentos e erro; reindexação pode exigir lotes. Não execute fragmentos aleatórios |

## Manutenção técnica

`npm.cmd test` instala nada nem acessa o seu backend: depois de `npm.cmd ci`, os testes rodam contra banco local em memória. Dados e chaves fictícios existem apenas em `tests` e nas simulações, que não são publicados em `dist`.

O teste de navegador é opcional e exige Playwright e Chromium. O pacote preserva o roteiro em `tests/browser-v5.cjs`; ele aceita `FGPT_BASE_PATH` e `FGPT_WEB_ROOT`. Não é necessário rodar testes para abrir o site ou fazer o build.

A distribuição acompanha as fontes de SQL e os geradores `scripts/package-v4.py`, `package-v5.py` e `package-install.py`. Os geradores não fazem conexão com Supabase e são opcionais. Os arquivos SQL entregues já estão gerados e corrigidos.

Os procedimentos técnicos precisam ser revisados pelo responsável pelo acervo. Busca aproximada apresenta candidatos; a fonte, revisão e aplicabilidade do procedimento continuam sendo decisivas. Esta versão não inventa instruções nem usa uma API de modelo para produzir respostas.
