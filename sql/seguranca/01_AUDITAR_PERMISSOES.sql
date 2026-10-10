-- FALHAS GPT - AUDITORIA DE SEGURANCA (somente leitura)
-- Execute no SQL Editor do projeto Supabase REAL, com o papel postgres.
-- Nenhuma instrucao altera usuarios, REs, procedimentos, grants ou policies.
-- "OK" = teste de configuracao aprovado. Nao substitui testes HTTP com token de operador.

WITH verificacoes(item,aprovado) AS (
 VALUES
 ('Schema privado nao acessivel por anon',
   NOT has_schema_privilege('anon','falhas_gpt','USAGE')),
 ('RLS habilitado em tabelas sensiveis',
   (SELECT count(*)=7 AND bool_and(c.relrowsecurity)
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='falhas_gpt' AND c.relname=ANY(ARRAY[
     'administradores','res_liberados','perfis','auditoria','procedimentos','anexos','acessos']) AND c.relkind='r')),
 ('Operadores nao podem alterar a tabela administradores',
   NOT (has_table_privilege('authenticated','falhas_gpt.administradores','INSERT')
     OR has_table_privilege('authenticated','falhas_gpt.administradores','UPDATE')
     OR has_table_privilege('authenticated','falhas_gpt.administradores','DELETE'))),
 ('Operadores nao podem alterar a tabela de REs',
   NOT (has_table_privilege('authenticated','falhas_gpt.res_liberados','INSERT')
     OR has_table_privilege('authenticated','falhas_gpt.res_liberados','UPDATE')
     OR has_table_privilege('authenticated','falhas_gpt.res_liberados','DELETE'))),
 ('Operadores nao podem editar procedimentos diretamente',
   NOT (has_table_privilege('authenticated','falhas_gpt.procedimentos','INSERT')
     OR has_table_privilege('authenticated','falhas_gpt.procedimentos','UPDATE')
     OR has_table_privilege('authenticated','falhas_gpt.procedimentos','DELETE'))),
 ('Anonimo nao executa liberacao de RE',
   NOT coalesce(has_function_privilege('anon',to_regprocedure('public.fgpt_admin_liberar_res_v4(text[])'),'EXECUTE'),true)),
 ('Anonimo nao executa exclusao de procedimentos',
   NOT coalesce(has_function_privilege('anon',to_regprocedure('public.fgpt_admin_excluir_procedimento_v5(uuid,integer)'),'EXECUTE'),true)),
 ('Anonimo nao executa sessao privada',
   NOT coalesce(has_function_privilege('anon',to_regprocedure('public.fgpt_sessao_v4()'),'EXECUTE'),true)),
 ('RPC de liberar RE confere admin no banco',
   coalesce((SELECT p.prosecdef AND position('falhas_gpt.exigir_admin' IN pg_get_functiondef(p.oid))>0
     FROM pg_proc p WHERE p.oid=to_regprocedure('public.fgpt_admin_liberar_res_v4(text[])')),false)),
 ('RPC de alterar RE confere admin no banco',
   coalesce((SELECT p.prosecdef AND position('falhas_gpt.exigir_admin' IN pg_get_functiondef(p.oid))>0
     FROM pg_proc p WHERE p.oid=to_regprocedure('public.fgpt_admin_alterar_re_v4(text,boolean)')),false)),
 ('RPC de salvar procedimento confere admin no banco',
   coalesce((SELECT p.prosecdef AND position('falhas_gpt.exigir_admin' IN pg_get_functiondef(p.oid))>0
     FROM pg_proc p WHERE p.oid=to_regprocedure('public.fgpt_admin_salvar_procedimento_v4(jsonb,uuid,integer)')),false)),
 ('RPC de excluir procedimento confere admin no banco',
   coalesce((SELECT p.prosecdef AND position('falhas_gpt.exigir_admin' IN pg_get_functiondef(p.oid))>0
     FROM pg_proc p WHERE p.oid=to_regprocedure('public.fgpt_admin_excluir_procedimento_v5(uuid,integer)')),false)),
 ('Funcao e_admin consulta tabela interna (nao metadados do navegador)',
   coalesce((SELECT p.prosecdef AND position('falhas_gpt.administradores' IN pg_get_functiondef(p.oid))>0
     FROM pg_proc p WHERE p.oid=to_regprocedure('falhas_gpt.e_admin()')),false)),
 ('View de procedimentos respeita RLS do chamador',
   coalesce((SELECT 'security_invoker=true'=ANY(c.reloptions)
     FROM pg_class c WHERE c.oid=to_regclass('public.vw_fgpt_acervo_v3')),false)),
 ('Trigger de cadastro por RE esta habilitado',
   EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='fgpt_validar_cadastro_v4' AND tgenabled IN ('O','A'))),
 ('Bucket de PDFs nao e publico',
   coalesce((SELECT NOT public FROM storage.buckets WHERE id='falhas-gpt-procedimentos'),false)),
 ('Barreiras restritivas de Storage instaladas',
   (SELECT count(*)=4 FROM pg_policy p
    JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='storage' AND c.relname='objects' AND NOT p.polpermissive
    AND p.polname=ANY(ARRAY[
     'fgpt_pdf_barreira_select_v4','fgpt_pdf_barreira_insert_v4',
     'fgpt_pdf_barreira_delete_v4','fgpt_pdf_barreira_update_v4'])))
)
SELECT item,CASE WHEN aprovado THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM verificacoes ORDER BY CASE WHEN aprovado THEN 1 ELSE 0 END,item;

-- Inventario de RPCs relevantes. Execute e analise funcoes antigas inesperadas
-- (ex.: buscar_fgpt_v2) antes de mudar seus privilegios.
-- Funcao EXECUTAVEL por authenticated NAO implica permissao administrativa:
-- toda RPC de escrita precisa checar e_admin no servidor.
SELECT n.nspname AS schema, p.proname AS funcao,
 pg_get_function_identity_arguments(p.oid) AS argumentos,
 p.prosecdef AS security_definer,
 has_function_privilege('anon',p.oid,'EXECUTE') AS anon_executa,
 has_function_privilege('authenticated',p.oid,'EXECUTE') AS autenticado_executa
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
AND (p.proname LIKE 'fgpt_%' OR p.proname LIKE 'buscar_fgpt_%'
 OR p.proname LIKE 'relacionados_fgpt_%' OR p.proname LIKE 'status_fgpt_%')
ORDER BY p.proname,argumentos;
