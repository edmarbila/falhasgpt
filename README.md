# Falhas GPT — pacote completo para Supabase e Pages

**Distribuição 5.1.0 · 08/10/2026 · banco V5 corrigido**

Projeto completo do Falhas GPT com CharleIA, login/cadastro por RE, administração, procedimentos, restabelecimentos, PDF/Excel e busca aproximada por relevância dentro dos textos. Esta distribuição acrescenta a instalação consolidada e a compatibilidade com hospedagem em subpasta. A versão do banco continua sendo 5.

O pacote contém o código e a estrutura do banco. **Não é um backup do seu Supabase atual:** não inclui seus procedimentos, contas, senhas, REs reais nem os PDFs armazenados. A conexão vem vazia. Nenhum novo site foi publicado com este pacote.

## Comece aqui

1. Extraia em uma pasta nova, por exemplo `D:\Apps\FalhasGPT`. A pasta correta é a que contém **este README, `package.json`, `public`, `sql` e `.github`**.
2. Se for usar o banco atual já corrigido, apenas valide com `sql/instalacao/02_VALIDAR_INSTALACAO_COMPLETA.sql`. Se for um Supabase novo, siga [a instalação do zero](docs/01_SUPABASE.md).
3. Configure a conexão conforme a seção abaixo.
4. Para testar no PC, execute `INICIAR_TESTE_LOCAL.cmd`, com Node.js 22 ou superior instalado. Abra `http://localhost:4173/` e mantenha a janela aberta. Não abra `index.html` por duplo clique.
5. Para hospedar com atualizações por Git, siga **[Cloudflare Pages conectado ao GitHub](docs/02_CLOUDFLARE_PAGES.md)**. Também há [GitHub Pages](docs/03_GITHUB_PAGES.md).
6. Execute o [roteiro de testes práticos](docs/04_TESTES_PRATICOS.md) antes de cadastrar o acervo definitivo.

Se o ZIP criar uma pasta a mais, mova **o conteúdo inteiro** da pasta do projeto para `D:\Apps\FalhasGPT`. Não suba apenas o `index.html`.

## Onde colar a URL e a chave

O exemplo está em **`public/project-config.example.js`**. Copie-o para **`public/project-config.js`** e preencha:

```js
export const PUBLIC_PROJECT = {
  url: 'https://SEU-PROJETO.supabase.co',
  key: 'sb_publishable_COLE_AQUI_SUA_CHAVE_PUBLICA'
};
```

Use a URL do projeto e a chave **publishable**; a antiga chave **anon** também é aceita. Nunca use `service_role`, `sb_secret_`, senha do banco ou token de administração. As chaves públicas são visíveis no navegador por definição; o bloqueio de acesso é feito pelo login, RE e políticas do banco.

Você também pode manter o arquivo vazio e configurar estas duas variáveis no provedor de deploy:

| Variável | Valor |
| --- | --- |
| `FGPT_SUPABASE_URL` | URL HTTPS do projeto |
| `FGPT_SUPABASE_PUBLIC_KEY` | Chave pública publishable ou anon |

As variáveis, quando preenchidas, têm prioridade no **build** sobre o arquivo. Depois de alterá-las, faça um novo deploy. Elas não são lidas em tempo real pelo navegador. Este projeto não lê `.env` automaticamente. Para teste local, use o arquivo JS.

Com a conexão central preenchida, o site abre em login/cadastro sem pedir configuração a cada visitante. O comando `npm run build:pages` recusa configuração ausente, incompleta ou chave privada conhecida.

## O que subir para cada lugar

| Destino | O que enviar |
| --- | --- |
| Repositório GitHub | Todo o projeto extraído, incluindo `.github`, `public`, `sql`, `scripts`, `tests`, `licenses`, `docs`, `package.json`, `package-lock.json`, `build.mjs` e `server.mjs` |
| Supabase SQL Editor | Apenas os SQLs da rota escolhida em [sql/README.md](sql/README.md) |
| Hospedagem estática / upload manual | **Somente o conteúdo da pasta `dist`**, gerada pelo build; `index.html` precisa ficar na raiz do upload |
| Cloudflare Pages com Git | O provedor lê o repositório, executa `npm run build:pages` e publica `dist` |
| GitHub Pages com Actions | O workflow incluído gera e envia apenas `dist` |

Não envie `node_modules`, `.git`, backups, credenciais privadas, exportações do banco ou documentos reais para a hospedagem. O `.gitignore` já exclui dependências e saída de build. A pasta `dist` é gerada na sua máquina ou no deploy e **não vem pronta/configurada neste ZIP**.

## Comandos no Windows

```powershell
cd "D:\Apps\FalhasGPT"
node --version
node server.mjs --open
```

Para gerar os arquivos de hospedagem depois de configurar a conexão:

```powershell
cd "D:\Apps\FalhasGPT"
npm.cmd run build:pages
```

Ou dê duplo clique em `GERAR_SITE_PAGES.cmd`. O build usa somente recursos do Node; não precisa instalar dependências para gerar ou abrir o site. `npm.cmd` evita o bloqueio de `npm.ps1` pela política do PowerShell.

Para rodar os testes automatizados, as dependências de desenvolvimento são necessárias:

```powershell
npm.cmd ci
npm.cmd test
```

## Privacidade da URL

O login do Falhas GPT protege o acervo pelo Supabase. Isso é diferente de impedir que alguém veja a tela de login. Para restringir a própria URL em Cloudflare Pages, configure **Cloudflare Access em produção e previews**, conforme o guia.

GitHub Pages normalmente disponibiliza a página na internet mesmo quando o repositório é privado. O workflow deste pacote fica desativado até você definir `FGPT_ENABLE_GITHUB_PAGES=true`. Deixe-o desativado se usar Cloudflare Pages. O pacote não altera a audiência da hospedagem privada já existente.

## Guias e manutenção

- [Supabase novo, banco atual e Auth](docs/01_SUPABASE.md)
- [Cloudflare Pages + GitHub + Access](docs/02_CLOUDFLARE_PAGES.md)
- [GitHub Pages e workflow](docs/03_GITHUB_PAGES.md)
- [Testes em celular e desktop](docs/04_TESTES_PRATICOS.md)
- [Atualizações, retorno à versão anterior e diagnóstico](docs/05_MANUTENCAO.md)
- [Auditoria de segurança, proteção de RE e hospedagem privada](docs/06_AUDITORIA_SEGURANCA.md)
- [SQL de auditoria de permissões (somente leitura)](sql/seguranca/01_AUDITAR_PERMISSOES.sql)
- [Escolher os SQLs corretos](sql/README.md)

Os guias V4/V5 anteriores e os SQLs históricos foram preservados para referência. **Para esta distribuição, siga este README e `sql/README.md`; não execute todos os arquivos SQL em sequência.**

A busca é textual aproximada, com palavras semelhantes e equivalências cadastradas; não gera procedimentos por IA. PDF digitalizado como imagem precisa de OCR externo antes da importação. O limite de PDF é 20 MiB. Não há serviço de e-mail próprio, Edge Function ou cron obrigatório nesta versão.
