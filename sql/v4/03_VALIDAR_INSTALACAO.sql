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
