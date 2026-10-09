# Supabase: do zero ou usando o projeto atual

## A. Continuar com o banco que já está funcionando

Use a mesma URL e chave pública. Se já aplicou a V5 corrigida, não há SQL novo para a compatibilidade com Pages: execute apenas `sql/instalacao/02_VALIDAR_INSTALACAO_COMPLETA.sql` e configure a nova URL de retorno do Auth. Procedimentos, contas e PDFs continuarão no mesmo Supabase.

Se ainda estiver na V4, aplique `sql/v5/04_ATUALIZAR_V4_PARA_V5.sql` inteiro e depois a validação completa. A correção de `pg_trgm` já está incorporada. Não reaplique o instalador V4 depois da V5.

## B. Criar um projeto novo

1. No painel Supabase, crie um projeto e aguarde os serviços ficarem disponíveis. Guarde a senha do banco em local seguro; ela não entra no site.
2. Em **Authentication > Users**, crie a conta inicial do administrador com e-mail e senha. Use a opção de confirmar a conta no painel, quando disponível, ou confirme o e-mail. **Crie pelo painel Auth; não faça INSERT manual em `auth.users`.**
3. Copie o UUID dessa conta. O UUID `35eadffb-84a8-499c-8a24-bdb0231ef2de` identifica o administrador do projeto anterior; um projeto novo terá outro UUID.
4. Abra `sql/instalacao/00_DIAGNOSTICO.sql` no SQL Editor. Em um projeto novo, `ja_existe_schema_falhas_gpt` deve ser `false`; Auth e Storage devem estar disponíveis.
5. Abra `sql/instalacao/01_INSTALAR_COMPLETO_V5.sql`. No início, altere **apenas**:

```sql
DECLARE admin_uuid_text text := 'COLE_UUID_ADMIN_AQUI';
```

Por exemplo, substitua o marcador pelo UUID real copiado de Auth. Não use e-mail, RE nem o ID de outro projeto.

6. Execute **o arquivo completo** no SQL Editor usando o papel administrativo do banco, normalmente `postgres`. Não escolha `anon` ou `authenticated`.
7. Aguarde a mensagem **Instalação completa V5 concluída**.
8. Execute `sql/instalacao/02_VALIDAR_INSTALACAO_COMPLETA.sql` inteiro. A última consulta deve retornar `instalacao_basica_ok=true`. Também devem existir as migrações 4 e 5, administrador ativo, bucket privado e os resultados de permissão indicados nos nomes das colunas.

O instalador consolida motor de busca, tabelas, índices, funções, RLS, admin, validação de RE, sequências, auditoria, PDFs privados, exclusão lógica e criação de tópicos. É uma única transação. **Ele bloqueia execução sobre um schema `falhas_gpt` já existente** para não reinstalar por cima do acervo. Isso é intencional; não apague o schema para contornar o bloqueio.

Os schemas `auth` e `storage` devem ser os fornecidos pelo Supabase. Este não é um instalador para PostgreSQL puro sem esses serviços. Extensões existentes são usadas no schema em que estão; nenhuma delas é movida.

## C. Configurações do Auth que o SQL não define

- Ative login por **e-mail/senha** e permita novos cadastros pelo site. O RE autorizado é conferido no backend.
- Mantenha a confirmação de e-mail para uso com operadores reais. Configure **SMTP próprio** no Supabase para entregar confirmações a essas pessoas. O SMTP padrão de testes restringe os destinatários e a quantidade de mensagens; um RE liberado não elimina essa restrição.
- Em **Authentication > URL Configuration**, configure o **Site URL** e adicione os endereços exatos de retorno que serão usados.

| Uso | Exemplo de URL com barra final |
| --- | --- |
| Cloudflare Pages | `https://SEU-SITE.pages.dev/` |
| GitHub Pages em repositório | `https://SEU-USUARIO.github.io/falhas-gpt/` |
| Domínio próprio | `https://falhas.seudominio.com/` |
| Teste local | `http://localhost:4173/` |

Use o endereço definitivo como Site URL. Em projeto compartilhado com outros aplicativos, preserve suas configurações e acrescente o retorno do Falhas GPT à lista; não remova retornos existentes sem avaliar o uso deles. Para preview, autorize somente os endereços específicos que vai testar.

Use o template padrão de confirmação com `{{ .ConfirmationURL }}`. Se você já personalizou o template, confira se respeita a URL de retorno, em vez de mandar sempre para a raiz de outro site. O app agora preserva a subpasta do GitHub Pages no retorno.

Este pacote não acrescenta CAPTCHA, MFA, login social ou fluxo próprio de esqueci a senha. Configurações adicionais que exijam esses fluxos precisam de integração específica no frontend. A criação, confirmação e gestão de contas continuam sob o Supabase Auth.

## C.1 Corrigir confirmação de e-mail que abre localhost:3000

Se o usuário confirmou a conta, mas o link termina em localhost:3000 e mostra ERR_CONNECTION_REFUSED, o Supabase confirmou o e-mail, mas tentou abrir um servidor local inexistente no celular.

No painel do Supabase abra Authentication > URL Configuration:

1. Site URL: https://edmarbila.github.io/falhasgpt/ (se esse for o endereço publicado no GitHub Pages).
2. Redirect URLs: adicione exatamente https://edmarbila.github.io/falhasgpt/ mantendo as URLs já utilizadas por outros projetos.
3. Authentication > Email Templates > Confirm sign up: mantenha o padrão ConfirmationURL, sem URL localhost escrita manualmente.
4. Confirme um cadastro novo no celular: o retorno deve abrir Falhas GPT e exibir “E-mail confirmado com sucesso! Faça login para acessar o Falhas GPT.”.
5. Se a conta já foi confirmada, entre normalmente com e-mail e senha na URL publicada. O link já utilizado não volta a mostrar o sucesso.

Para Cloudflare Pages ou domínio próprio, use a URL real do site em vez do exemplo GitHub Pages. O nome do repositório é falhasgpt, sem hífen.

## D. Conexão e API

Copie **Project URL** e a chave **publishable** no diálogo **Connect** / configurações de **API Keys** do projeto. A chave `anon` legada também funciona. Preencha o arquivo de configuração conforme o README ou as variáveis do deploy. URL e chave precisam pertencer ao mesmo projeto.

A Data API deve estar habilitada e expor o schema `public` (padrão usual). A interface usa as views e RPCs de `public`; não é necessário expor `falhas_gpt` na API. Não transforme o bucket em público e não abra políticas para `anon` para corrigir erros de acesso.

A chave pública identifica o aplicativo, enquanto o login identifica o usuário. O token de sessão e o RE ativo determinam a leitura do acervo. O administrador é definido na tabela protegida do banco, não por e-mail ou metadados enviados pelo navegador.

## E. Primeiro uso

1. Entre no site com a conta inicial do administrador.
2. Abra **Administração > Liberação de RE**. Libere um RE no formato `59-00000` ou importe uma planilha e revise a lista encontrada antes de confirmar.
3. Em outra aba/navegador, cadastre um operador com o RE liberado e confirme o e-mail.
4. Crie um procedimento de teste com título, categoria, série/aplicabilidade, resumo, texto completo, fonte e revisão. Revise e disponibilize para aparecer ao operador.
5. Teste o PDF, a pesquisa e a revogação conforme `04_TESTES_PRATICOS.md`.

Um RE revogado continua no histórico e não é reativado automaticamente pela importação. A revogação bloqueia acesso; não apaga a conta Auth nem todos os seus dados. Ao migrar para outro projeto, usuários e arquivos não são transferidos por este instalador. Preserve o backup real do banco e os objetos do Storage se desejar transportar o acervo.

Referências: [chaves](https://supabase.com/docs/guides/getting-started/api-keys), [URLs de retorno](https://supabase.com/docs/guides/auth/redirect-urls), [SMTP](https://supabase.com/docs/guides/auth/auth-smtp).
