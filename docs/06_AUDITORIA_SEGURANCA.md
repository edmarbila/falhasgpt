# Falhas GPT: seguranca, repositorio publico e auditoria

## Resultado da revisao do codigo versionado (09/10/2026)
- Nao foram encontrados arquivos `.env`, chave `service_role`, chave `sb_secret_`, senha real ou token administrativo nos arquivos revisados e historico inicial de commits.
- A URL do Supabase e a chave `sb_publishable_` ou `anon` foram projetadas para o navegador e nao sao segredos. NUNCA use `service_role` ou `sb_secret_` no frontend, Pages ou Git.
- Existe identificador UUID de conta administradora em SQLs legados e exemplos. Nao e uma chave de acesso, mas e informacao de conta; evita-se publicar esse tipo de dado no futuro.
- Procedimentos reais, contas Auth e REs vinculados nao foram incorporados nos arquivos estaticos revisados. Isso NAO prova que o banco real esteja seguro nem que backups historicos nao tenham sido publicados em outro lugar.

## 1. Teste do Supabase REAL antes da producao
Abra SQL Editor e execute `sql/seguranca/01_AUDITAR_PERMISSOES.sql`.
Resultado esperado: todos os testes da primeira consulta = `OK`.
Se algum aparecer `REVISAR`, nao afrouxe o RLS e nao mude as permissoes por tentativa. Identifique qual instalacao/migracao foi realmente aplicada e a causa.
A segunda consulta lista RPCs antigas: revise especialmente `buscar_fgpt_v2` e outras funcoes publicas herdadas. Nao remova RPCs de outros projetos sem avaliar dependencias.

Execute, depois, testes com TRES identidades reais (conta anon sem token, operador e administrador):
- Anon: nenhuma leitura do acervo ou execucao das RPCs de admin; confirmacao e signup devem respeitar as configuracoes do Auth.
- Operador: ver somente publicados, nunca rascunhos; chamada direta a RPC de liberar RE deve negar mesmo que o navegador mostre artificialmente `admin=true`; tentativa de `UPDATE` em tabelas administrativas deve negar. Verifique que outras contas nao podem ver PDFs.
- Administrador: consegue liberar RE e editar acervo, com historico de auditoria e sem service_role no browser.
Nao use um RE real na simulacao; use usuario de teste, e RE de teste criado pelo administrador.

## 2. Fragilidade restante: cadastramento somente com RE
O sistema atual impede que um RE NAO liberado seja usado e impede reutilizar um RE ja vinculado.
Entretanto, o primeiro solicitante que souber um RE liberado AINDA SEM USUARIO pode registrar-se com um e-mail proprio e reivindica-lo.
Isto nao autoriza a pessoa como admin, mas pode dar acesso de operador ao acervo.
Plano de correcao recomendado (exige migracao coordenada com o painel):
1. No ato de liberar o RE, registrar o e-mail exato do funcionario (idealmente corporativo) e confirmar quem e seu dono.
2. No trigger de cadastro e na RPC de vinculo, exigir a combinacao RE + e-mail permitido + e-mail confirmado no Auth.
3. Revogar/revisar liberações pendentes sem email vinculado; preservar as contas ja ativas.
4. Disponibilizar opcoes administrativas para corrigir e-mail autorizado e revogar acessos, com auditoria.
5. Aplicar limite de tentativas, CAPTCHA no signup e MFA para administradores conforme configuracao Supabase.
Nao altere o cadastro em producao antes de definir como receber os e-mails dos REs pendentes; uma restricao imediata quebraria os novos cadastros.

## 3. Repositorio privado e hospedagem
- Cloudflare Pages Free aceita GitHub privado e builds automaticos. O codigo servido aos visitantes segue publico se a URL publicada estiver aberta.
- Netlify Free permite repositorios privados, mas a visibilidade de deploy *privado* no plano Free e basicamente para o dono, nao para diversos operadores.
- Vercel Hobby permite uso pessoal com repositorio privado sob regras de titularidade, mas restringe uso comercial.
- GitHub Pages com repositorio privado geralmente exige plano pago do GitHub.
- Se e necessario proteger ate a tela e os arquivos estaticos, avalie Cloudflare Access, observando limite do plano gratuito e o cadastro dos operadores.
- Nenhuma opcao de hospedagem substitui RLS, autorizacao de funcoes SQL e autenticacao de usuario.

## 4. Boas praticas permanentes
- `.env`, dumps, PDFs sigilosos, tokens e service_role nunca entram no Git. Use variaveis apenas para chaves PUBLICAS durante o build do site.
- Se um segredo real ja esteve em qualquer commit, torna-lo privado ou remove-lo da branch atual NAO basta: revogue/rotacione a credencial e trate historico e forks.
- No GitHub configure revisao de dependencias e protecao de branch. Rode `npm test` antes de publicar, principalmente `tests/v4-security.test.mjs` e `tests/v5.test.mjs`.
- No Supabase: confirmacao de e-mail habilitada; MFA para administrador; email corporativo autorizado por RE; limite de cadastros e captcha; revise logs do Auth e da tabela de auditoria.
- Usuarios autenticados podem inspecionar e copiar os procedimentos aos quais tem acesso; nao existe maneira confiavel de impedir copia usando so HTML/JS.
- Nunca use autorizacao vinda de `localStorage`, `user_metadata.admin`, parametro de URL ou botao oculto como prova de ser admin. O banco deve consultar sua tabela de administradores ligada ao `auth.uid()`.

Esta revisao e estatica: o banco em producao, as chaves ativas, o painel de Auth e as redes nao foram auditados diretamente.
