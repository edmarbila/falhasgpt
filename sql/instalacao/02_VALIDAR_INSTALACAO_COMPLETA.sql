-- Somente leitura. Execute após os arquivos 01 e 02.
SELECT versao,aplicado_em FROM falhas_gpt.migracoes ORDER BY versao;
SELECT usuario_id,ativo FROM falhas_gpt.administradores;
SELECT count(*) AS total,count(*) FILTER(WHERE ativo) AS liberados,
 count(*) FILTER(WHERE NOT ativo) AS revogados,count(usuario_id) AS vinculados FROM falhas_gpt.res_liberados;
SELECT codigo,numero_sequencial,topico,publicado,versao_edicao FROM falhas_gpt.procedimentos ORDER BY criado_em DESC LIMIT 20;
SELECT tgname,tgenabled FROM pg_trigger WHERE tgname='fgpt_validar_cadastro_v4';
SELECT id,public,file_size_limit,allowed_mime_types FROM storage.buckets WHERE id='falhas-gpt-procedimentos';
SELECT tablename,policyname,roles,cmd FROM pg_policies WHERE schemaname='falhas_gpt' OR (schemaname='storage' AND policyname LIKE 'fgpt_%');
SELECT has_function_privilege('anon','public.fgpt_admin_liberar_res_v4(text[])','execute') AS anon_pode_liberar_deve_ser_false;
SELECT has_table_privilege('authenticated','falhas_gpt.res_liberados','insert') AS operador_pode_gravar_re_deve_ser_false;
-- SQL Editor usa sessão administrativa sem login do aplicativo. Teste as RPCs autenticadas pelo site.

-- Somente leitura. Não concede acesso e não altera registros.
SELECT versao,aplicado_em FROM falhas_gpt.migracoes ORDER BY versao;
SELECT origem,count(*) AS trechos FROM falhas_gpt.termos_busca GROUP BY origem ORDER BY origem;
SELECT count(*) FILTER(WHERE excluido_em IS NULL) AS registros_ativos,
 count(*) FILTER(WHERE excluido_em IS NOT NULL) AS excluidos_com_historico FROM falhas_gpt.procedimentos;
SELECT has_function_privilege('anon','public.fgpt_admin_excluir_procedimento_v5(uuid,integer)','execute') AS anon_pode_excluir_deve_ser_false;
SELECT has_function_privilege('authenticated','public.fgpt_admin_topicos_v5(text,uuid[])','execute') AS rpc_disponivel_deve_ser_true;
-- Todos os campos abaixo devem ser true após aplicar o SQL 04 corrigido inteiro.
-- Confere a definição instalada, sem exigir login de operador no SQL Editor.
SELECT NOT EXISTS(SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) c
 WHERE c LIKE 'pg_trgm.%') AS sem_set_pg_trgm_deve_ser_true,
 position('similarity(t.normalizado,qn)>=0.15::real' IN p.prosrc)>0 AS limite_frase_explicito_deve_ser_true,
 position('word_similarity(qc,t.canonico)>=0.25::real' IN p.prosrc)>0 AS limite_trecho_explicito_deve_ser_true,
 NOT p.prosecdef AS busca_preserva_rls_deve_ser_true
FROM pg_proc p WHERE p.oid=to_regprocedure('public.buscar_fgpt_v3(text,integer,numeric)');
-- No aplicativo, como operador, pesquise uma palavra que exista apenas no texto completo.
-- O resultado deve indicar ocorrência no conteúdo e oferecer Ver trecho encontrado.

-- Deve ser true. Não substitui o teste prático com usuário administrador e operador.
SELECT EXISTS(SELECT 1 FROM falhas_gpt.migracoes WHERE versao=5)
 AND EXISTS(SELECT 1 FROM falhas_gpt.administradores a JOIN auth.users u ON u.id=a.usuario_id WHERE a.ativo)
 AND EXISTS(SELECT 1 FROM storage.buckets WHERE id='falhas-gpt-procedimentos' AND NOT public)
 AND NOT has_function_privilege('anon','public.buscar_fgpt_v3(text,integer,numeric)','execute')
 AND NOT has_function_privilege('anon','public.fgpt_admin_excluir_procedimento_v5(uuid,integer)','execute')
 AND NOT has_table_privilege('authenticated','falhas_gpt.res_liberados','insert')
 AS instalacao_basica_ok;
