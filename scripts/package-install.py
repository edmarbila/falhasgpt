"""Gera instalação nova V5 a partir dos SQLs corrigidos; não acessa banco nenhum."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
admin='35eadffb-84a8-499c-8a24-bdb0231ef2de'

def body(relative):
    text=(root/relative).read_text(encoding='utf-8')
    text=re.sub(r'^BEGIN;\s*$', '', text, flags=re.M)
    text=re.sub(r'^COMMIT;\s*$', '', text, flags=re.M)
    text=re.sub(r"^SELECT '[^'\n]*' (?:AS )?resultado;\s*$", '', text, flags=re.M)
    text=re.sub(r"^NOTIFY pgrst,\s*'reload schema';\s*$", '', text, flags=re.M)
    text=text.replace("'"+admin+"'",'(SELECT admin_id FROM pg_temp.fgpt_instalacao_config)')
    return text.replace('Administrador '+admin+' não existe','Administrador informado não existe')

header='''-- FALHAS GPT — INSTALAÇÃO NOVA COMPLETA V5 (distribuição 5.1.0, 08/10/2026)
-- Inclui motor de busca, admin, RE, procedimentos, PDFs privados e correções V5.
-- Pré-requisito: projeto Supabase PostgreSQL 15+ e administrador criado em Auth.
-- EDITE APENAS COLE_UUID_ADMIN_AQUI abaixo. Execute este arquivo INTEIRO.
-- Bloqueia instalação por cima de um acervo existente; use a rota de atualização.
BEGIN;
CREATE TEMP TABLE fgpt_instalacao_config(admin_id uuid NOT NULL) ON COMMIT DROP;
DO $config$
DECLARE admin_uuid_text text := 'COLE_UUID_ADMIN_AQUI';
BEGIN
 IF admin_uuid_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
  RAISE EXCEPTION 'Preencha o UUID do administrador no início deste arquivo. Copie de Authentication > Users.';
 END IF;
 IF to_regnamespace('falhas_gpt') IS NOT NULL THEN
  RAISE EXCEPTION 'Já existe um acervo Falhas GPT neste banco. Instalação nova cancelada. Use sql/v5/04_ATUALIZAR_V4_PARA_V5.sql para V4/V5; não apague o schema.';
 END IF;
 IF current_setting('server_version_num')::integer < 150000 THEN
  RAISE EXCEPTION 'Este instalador requer PostgreSQL 15 ou superior.';
 END IF;
 IF to_regclass('auth.users') IS NULL OR to_regclass('storage.objects') IS NULL THEN
  RAISE EXCEPTION 'Execute em um projeto Supabase com Auth e Storage disponíveis.';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=admin_uuid_text::uuid) THEN
  RAISE EXCEPTION 'Administrador não encontrado em Auth. Crie a conta no painel Supabase e copie o UUID deste projeto.';
 END IF;
 INSERT INTO pg_temp.fgpt_instalacao_config VALUES(admin_uuid_text::uuid);
END $config$;
'''
parts=[body('sql/v4/01_INSTALAR_ATUALIZACAO_V4.sql'),body('sql/v4/02_PDFS_PRIVADOS.sql'),body('sql/v5/04_ATUALIZAR_V4_PARA_V5.sql')]
result=header+'\n\n'.join(parts)+"\nNOTIFY pgrst,'reload schema';\nCOMMIT;\nSELECT 'Instalação completa V5 concluída. Execute 02_VALIDAR_INSTALACAO_COMPLETA.sql.' AS resultado;\n"
assert admin not in result
assert result.count('BEGIN;')==1 and result.count('COMMIT;')==1
assert 'SET pg_trgm.' not in result
(root/'sql/instalacao/01_INSTALAR_COMPLETO_V5.sql').write_text(result,encoding='utf-8')
validation=(root/'sql/v4/03_VALIDAR_INSTALACAO.sql').read_text(encoding='utf-8')+'\n'+(root/'sql/v5/05_VALIDAR_V5.sql').read_text(encoding='utf-8')
validation+='''
-- Deve ser true. Não substitui o teste prático com usuário administrador e operador.
SELECT EXISTS(SELECT 1 FROM falhas_gpt.migracoes WHERE versao=5)
 AND EXISTS(SELECT 1 FROM falhas_gpt.administradores a JOIN auth.users u ON u.id=a.usuario_id WHERE a.ativo)
 AND EXISTS(SELECT 1 FROM storage.buckets WHERE id='falhas-gpt-procedimentos' AND NOT public)
 AND NOT has_function_privilege('anon','public.buscar_fgpt_v3(text,integer,numeric)','execute')
 AND NOT has_function_privilege('anon','public.fgpt_admin_excluir_procedimento_v5(uuid,integer)','execute')
 AND NOT has_table_privilege('authenticated','falhas_gpt.res_liberados','insert')
 AS instalacao_basica_ok;
'''
(root/'sql/instalacao/02_VALIDAR_INSTALACAO_COMPLETA.sql').write_text(validation,encoding='utf-8')
print('Instalação completa e validação geradas, sem acesso ao banco.')
