# Cloudflare Pages ligado ao GitHub

Este caminho mantém o código em um repositório GitHub e gera um novo deploy quando você envia alterações para `main`. Para restringir a própria URL, use Cloudflare Access. O login por RE do Falhas GPT continua sendo necessário para acessar o Supabase.

## 1. Colocar o projeto no GitHub

No GitHub, crie um repositório chamado, por exemplo, `falhas-gpt`, inicialmente **Private**, vazio, sem gerar outro README. Copie a URL HTTPS do seu repositório.

Instale Git para Windows e Node.js 22 ou superior. Depois, no PowerShell, dentro da pasta do projeto extraído:

```powershell
cd "D:\Apps\FalhasGPT"
git init -b main
git add .
git status
git commit -m "Falhas GPT 5.1 completo"
git remote add origin https://github.com/SEU-USUARIO/falhas-gpt.git
git push -u origin main
```

Substitua `SEU-USUARIO` pelo seu usuário real. Faça a autenticação do GitHub quando o Git solicitar. Não coloque token na URL nem dentro dos arquivos. Esses comandos são para uma pasta nova sem Git; se já há repositório, mantenha-o e siga o guia de manutenção.

Confira no GitHub se estão presentes `package.json`, `build.mjs`, `public` e `.github`. Não deve existir uma pasta extra `SITE` ou `Falhas_GPT...` envolvendo todos os arquivos. Se você optar por essa organização, o campo **Root directory** do Pages precisa apontar para essa pasta.

## 2. Criar o projeto Pages

No painel Cloudflare, abra **Workers & Pages** e escolha criar uma aplicação **Pages**, conectada a um repositório Git. Não escolha criar um Worker com comando `wrangler deploy`.

Autorize o acesso somente ao repositório necessário e escolha `falhas-gpt`. Defina:

| Campo | Valor |
| --- | --- |
| Production branch | `main` |
| Framework preset | `None` |
| Root directory | vazio, quando `package.json` estiver na raiz |
| Build command | `npm run build:pages` |
| Build output directory | `dist` |
| `NODE_VERSION` | `22` |
| `FGPT_SUPABASE_URL` | URL HTTPS do Supabase |
| `FGPT_SUPABASE_PUBLIC_KEY` | Chave pública publishable ou anon |

As duas variáveis do Supabase são de **build** e acabam no JavaScript público gerado. Usar um campo chamado Secret não as torna privadas no navegador. Não informe chaves de administração. Se já preencheu `public/project-config.js`, as variáveis são opcionais; evite manter valores diferentes em dois lugares.

Salve e execute o primeiro deploy. O log deve indicar a geração de `dist` e concluir sem erro. A URL será fornecida pelo Cloudflare; não é necessário usar domínio próprio. Caso use previews, configure as variáveis também no ambiente Preview ou mantenha os previews desativados até configurar.

Este projeto não precisa de `wrangler.jsonc`, `assets.directory`, Worker, comando de deploy personalizado nem caminhos `D:\...` no Cloudflare. O build recebe somente caminhos relativos do repositório.

## 3. Manter a URL privada com Access

**Pages e seus previews são públicos por padrão.** Ativar o deploy na etapa anterior cria uma URL na internet. Se quiser impedir até a visualização da tela de login, planeje/configure o Access para os hostnames antes de disponibilizar a instância para uso. Não considere `noindex` ou um repositório privado como controle de acesso.

Depois de criar o projeto, no Pages:

1. Em **Settings > General**, habilite **Enable access policy** para os previews.
2. Abra **Manage** na política criada. No Cloudflare Zero Trust / Access, localize a aplicação correspondente.
3. Configure uma política **Allow** restrita ao seu e-mail ou aos e-mails expressamente autorizados. Não use uma regra de acesso para todos.
4. Para proteger também a produção `SEU-SITE.pages.dev`, ajuste a aplicação: no hostname, retire o wildcard `*` de `*.SEU-SITE.pages.dev`, ficando `SEU-SITE.pages.dev`, e salve. Ajuste o nome da aplicação se o painel pedir.
5. Volte ao Pages e habilite novamente a política de previews. Confira que há proteção para **os dois hostnames**: produção e `*.SEU-SITE.pages.dev`.
6. Caso use domínio próprio, crie também uma aplicação Access do tipo self-hosted para esse domínio, com a mesma restrição desejada.
7. Em uma janela anônima, teste produção, preview e domínio próprio. Antes do Falhas GPT deve aparecer o controle de acesso da Cloudflare, e uma pessoa não autorizada não deve conseguir entrar.

A proteção automática de previews sozinha **não protege a produção**. Os nomes dos menus podem variar; as instruções atuais do provedor estão nas referências ao final. Conferir a política efetiva faz parte da implantação, pois não é controlada pelo código deste ZIP.

O Access e o Supabase são dois controles separados. Mais tarde, para operadores, será preciso autorizá-los no Access e liberar seu RE no Falhas GPT. Não remova a proteção da URL apenas porque um RE foi liberado.

## 4. Retorno do cadastro e celular

No Supabase, acrescente a URL exata de produção, com barra final, às URLs de retorno do Auth. Siga `01_SUPABASE.md`. Isso permite retornar corretamente após confirmar o cadastro.

Abra a URL HTTPS no navegador do celular e faça login. O computador não precisa ficar ligado. O servidor `localhost:4173` é apenas para o teste no próprio PC; o celular usará a URL hospedada.

## 5. Atualizar pelo deploy

Edite os arquivos na mesma pasta do projeto e envie:

```powershell
cd "D:\Apps\FalhasGPT"
git status
git add .
git diff --cached --stat
git commit -m "Atualiza Falhas GPT"
git push origin main
```

O Cloudflare detecta o commit e atualiza a URL de produção. Acompanhe em **Deployments**. Não precisa apagar/recriar o projeto nem enviar `dist` ao Git. Se só cadastrou procedimentos/RE pelo painel, nada precisa de commit: esses dados já ficam no Supabase.

O workflow do GitHub Pages deve continuar desabilitado (`FGPT_ENABLE_GITHUB_PAGES` ausente ou diferente de `true`) para não manter outra publicação sem querer.

Referências: [integração Git](https://developers.cloudflare.com/pages/configuration/git-integration/), [sites estáticos](https://developers.cloudflare.com/pages/framework-guides/deploy-anything/), [previews e Access](https://developers.cloudflare.com/pages/configuration/preview-deployments/), [Access na produção e domínio próprio](https://developers.cloudflare.com/pages/platform/known-issues/#enable-access-on-your-pagesdev-domain).
