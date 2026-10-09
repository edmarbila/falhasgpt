-- Somente leitura. Resultado necessário para adaptar/importar seu acervo antigo sem adivinhar colunas.
SELECT n.nspname AS schema,f.proname AS funcao,
 pg_get_function_identity_arguments(f.oid) AS assinatura,
 pg_get_function_arguments(f.oid) AS argumentos,
 pg_get_function_result(f.oid) AS retorno,
 pg_get_functiondef(f.oid) AS definicao
FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace
WHERE f.proname IN ('buscar_fgpt_v2','buscar_fgpt_v3') ORDER BY n.nspname,f.proname;
SELECT table_schema,table_name,column_name,data_type,ordinal_position
FROM information_schema.columns
WHERE table_schema NOT IN ('pg_catalog','information_schema','auth','storage','realtime','vault','extensions')
AND (table_name ILIKE '%proced%' OR table_name ILIKE '%fgpt%' OR table_name ILIKE '%topico%' OR table_name ILIKE '%restabel%')
ORDER BY table_schema,table_name,ordinal_position;
