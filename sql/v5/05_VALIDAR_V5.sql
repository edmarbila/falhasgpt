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
