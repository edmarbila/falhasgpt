-- Somente leitura. Confirme o projeto ANTES de instalar.
SELECT version() AS postgresql, current_database() AS banco;
SELECT id,email FROM auth.users WHERE id='35eadffb-84a8-499c-8a24-bdb0231ef2de';
SELECT table_schema,table_name,column_name,data_type FROM information_schema.columns
WHERE table_schema='falhas_gpt' ORDER BY table_name,ordinal_position;
SELECT n.nspname AS schema,p.proname,pg_get_function_identity_arguments(p.oid) AS argumentos
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.proname IN('buscar_fgpt_v2','buscar_fgpt_v3','fgpt_sessao_v4');
-- Outros triggers do projeto são apenas listados, nunca removidos.
SELECT tgname,pg_get_triggerdef(oid) AS definicao FROM pg_trigger WHERE tgrelid='auth.users'::regclass AND NOT tgisinternal;
