-- Somente leitura. Execute no SQL Editor do Supabase antes de escolher a rota.
SELECT current_database() AS banco,current_setting('server_version') AS versao_postgresql,
 to_regnamespace('falhas_gpt') IS NOT NULL AS ja_existe_schema_falhas_gpt,
 to_regclass('falhas_gpt.migracoes') IS NOT NULL AS tem_tabela_migracoes,
 to_regprocedure('public.fgpt_sessao_v4()') IS NOT NULL AS tem_funcoes_v4,
 to_regprocedure('public.fgpt_admin_excluir_procedimento_v5(uuid,integer)') IS NOT NULL AS tem_funcoes_v5,
 to_regclass('auth.users') IS NOT NULL AS auth_disponivel,
 to_regclass('storage.objects') IS NOT NULL AS storage_disponivel;
SELECT e.extname,n.nspname AS schema_extensao FROM pg_extension e
 JOIN pg_namespace n ON n.oid=e.extnamespace WHERE e.extname IN ('pg_trgm','fuzzystrmatch');
-- Sem schema Falhas GPT: rota de instalação nova (01 e 02 desta pasta).
-- Com V4/V5: preserve o acervo, veja sql/README.md. Não execute o instalador novo.
-- Schema existente sem V4: verifique a instalação antiga antes de atualizar.
