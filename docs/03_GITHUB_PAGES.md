# GitHub Pages — alternativa de hospedagem

O site foi ajustado para URLs em subpasta, como `https://SEU-USUARIO.github.io/falhas-gpt/`. Imagens, fontes, JavaScript, leitor de planilhas, worker PDF e retorno do cadastro preservam essa subpasta.

**GitHub Pages normalmente publica a interface na internet, inclusive quando a origem é um repositório privado.** Uma URL privada tem requisitos específicos de plano/organização. O login/RE protege os dados do Supabase, mas não oculta os arquivos estáticos ou a tela de login. Para a exigência de URL privada, prefira a rota Cloudflare Pages + Access. Não habilite este workflow até aceitar o modelo de visibilidade da sua conta.

## 1. Repositório

Suba o projeto inteiro na raiz do repositório, como explicado no primeiro passo de `02_CLOUDFLARE_PAGES.md`. O workflow já está em `.github/workflows/pages.yml`; ele publica **somente `dist`**, não a pasta SQL nem os testes.

O plano GitHub Free oferece Pages para repositórios públicos. Verifique se o seu plano permite Pages com repositório privado; não altere o repositório para público apenas para remover um erro de plano.

## 2. Variáveis

No repositório, abra **Settings > Secrets and variables > Actions > Variables** e cadastre:

| Nome | Valor |
| --- | --- |
| `FGPT_SUPABASE_URL` | URL HTTPS do Supabase |
| `FGPT_SUPABASE_PUBLIC_KEY` | Chave pública publishable ou anon |
| `FGPT_ENABLE_GITHUB_PAGES` | `true`, somente ao decidir ativar esta publicação |

A alternativa às duas primeiras variáveis é preencher `public/project-config.js`. O workflow exige uma conexão configurada. Não cadastre `service_role`, chave secret ou senha aqui.

## 3. Ativar o deploy

1. Em **Settings > Pages > Build and deployment > Source**, escolha **GitHub Actions**.
2. Na aba **Actions**, abra **Publicar Falhas GPT no GitHub Pages**.
3. Escolha **Run workflow** e a branch `main`, ou envie um novo commit para `main`.
4. Aguarde os jobs `build` e `deploy` terminarem. A URL aparecerá no ambiente `github-pages` e nas configurações de Pages.
5. Confira HTTPS e abra a URL completa com `/falhas-gpt/`, incluindo a barra final.
6. Adicione **essa URL completa** no Auth do Supabase. A raiz `https://SEU-USUARIO.github.io/` não equivale à subpasta do projeto.
7. Teste no celular seguindo `04_TESTES_PRATICOS.md`.

Não é preciso criar branch `gh-pages`, selecionar a pasta `/docs`, executar Jekyll ou enviar a pasta `public` como raiz de um deploy por branch. O workflow incluído faz a publicação pelo artefato gerado.

## 4. Atualizações e desativação

Depois da ativação, cada `git push origin main` dispara o deploy. Alterar apenas variáveis exige rodar novamente o workflow. O banco não é alterado pelo deploy; SQLs devem ser aplicados separadamente quando uma versão realmente exigir migração.

Para parar deploys futuros, remova `FGPT_ENABLE_GITHUB_PAGES` ou mude seu valor. Isso **não remove uma publicação já existente**. Para retirar o site do ar, use o controle de despublicação/desativação em Settings > Pages. Não habilite GitHub Pages se já estiver usando apenas Cloudflare e não desejar uma segunda URL.

Referências: [workflows de Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages), [fontes de publicação e visibilidade](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site), [planos compatíveis](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages).
