# Falhas GPT — correção do SQL V4 → V5

Correção de 08/10/2026 para o erro:

`ERROR: 42501: permission denied to set parameter "pg_trgm.similarity_threshold"`

## O que executar agora

1. Extraia este ZIP em uma pasta nova, por exemplo `D:\Apps\FalhasGPT_Correcao_SQL`.
2. Abra o **SQL Editor do mesmo projeto Supabase** em que a V4 foi instalada. Use o papel de administração do banco que já usou na instalação, normalmente `postgres`; não selecione `anon` ou `authenticated`. Não é necessário conceder novos privilégios nem alterar configurações globais.
3. Se aparecer `current transaction is aborted`, execute somente `ROLLBACK;` e depois continue. Não use `COMMIT` para tentar concluir uma execução que falhou.
4. Abra **04_ATUALIZAR_V4_PARA_V5.sql** deste ZIP, copie **todo o conteúdo** para uma consulta nova e execute sem selecionar apenas um trecho. Ele substitui o SQL 04 anterior.
5. Aguarde a mensagem **V5 corrigida instalada: busca sem SET pg_trgm, conteúdo completo, exclusão administrativa e criação de tópicos.**
6. Execute **05_VALIDAR_V5.sql**, também deste ZIP. É somente leitura.
7. Atualize o site com `Ctrl+F5` e faça uma busca por um termo que exista apenas no conteúdo de um procedimento publicado. Teste também uma pequena variação de escrita. Se o mesmo termo for o título exato de outro procedimento, esse título deve ficar acima do resultado encontrado apenas no conteúdo.

**Não rode os SQLs 01/02/03 nem reinstale a V4 para corrigir este erro.** Não é necessário executar o atualizador do site nem substituir `project-config.js`. Este pacote contém somente os SQLs e esta orientação; não altera arquivos do seu computador, credenciais, usuários ou a visibilidade da hospedagem.

## Resultado esperado do SQL 05

- A tabela de migrações deve incluir a **versão 5**.
- As origens `resumo` e `conteudo` terão trechos quando existirem textos preenchidos no acervo.
- `anon_pode_excluir_deve_ser_false` deve ser **false**.
- `rpc_disponivel_deve_ser_true` deve ser **true**.
- Na última consulta, os quatro campos devem ser **true**: ausência de SET pg_trgm, limite explícito de frase, limite explícito de trecho e busca com as permissões de quem consulta.

Se o SQL 04 falhar, pare e envie o erro completo. Se o SQL 05 apresentar resultado diferente, envie os resultados. Não apague tabelas, políticas ou extensões.

## Por que aconteceu e o que foi corrigido

A função enviada anteriormente continha `SET pg_trgm.similarity_threshold=0.15` e `SET pg_trgm.word_similarity_threshold=0.25`. A criação dessa função foi rejeitada por falta de permissão para definir o parâmetro nessa sessão. Isso pode ocorrer em uma conexão nova antes de a biblioteca da extensão registrar seus parâmetros.

A correção remove os dois SETs e usa diretamente os resultados de `similarity(...) >= 0.15` e `word_similarity(...) >= 0.25`. Não basta apagar somente os SETs: os antigos operadores `%` e `%>` dependem dos limites da sessão e poderiam restringir os resultados. Por isso, as comparações também foram substituídas.

A extensão já instalada é usada no schema em que se encontra, seja `public` ou `extensions`; ela não é movida nem reinstalada. A RPC continua `buscar_fgpt_v3`, com o mesmo formato de retorno. Mantêm-se a ordenação por relevância, os pesos de título/aliases/resumo/conteúdo, a busca aproximada, os trechos encontrados e as regras de acesso.

Os filtros numéricos de similaridade podem exigir mais leitura do índice de termos do que os operadores indexáveis. Não foi medido o desempenho do seu acervo real; se a busca ficar lenta com muitos documentos, informe o volume e a consulta para uma otimização específica.

Referência técnica: [pg_trgm — funções, operadores e parâmetros](https://www.postgresql.org/docs/current/pgtrgm.html).

## Preservação e testes

O SQL 04 é reaplicável e usa `BEGIN`/`COMMIT`. Se você executou o arquivo anterior inteiro e recebeu o erro informado, aquela transação não foi concluída; não é necessário apagar nada para tentar novamente. A atualização preserva usuários, REs, conteúdo, identificadores e histórico. Ela instala as funções V5 e reindexa os textos existentes. Mantenha o backup habitual antes de qualquer migração.

A correção foi validada em PostgreSQL local via PGlite, com banco de teste e usuário sem superprivilégio: reprodução do erro em conexão nova, rollback da migração com falha, instalação corrigida, reaplicação e pesquisa com limites de sessão diferentes. Também foram conferidos os schemas `public` e `extensions`, prioridade dos resultados, trechos e controles de acesso.

**Não executei este SQL no seu Supabase real.** Este arquivo não contém credenciais e a aplicação no seu projeto é feita pelos passos acima.
