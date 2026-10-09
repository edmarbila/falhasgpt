from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
base=(root/'sql/01_instalar_motor_busca.sql').read_text(encoding='utf-8')
base=base[:base.index("-- Reprocessa índices")]
base=base.replace('BEGIN;', '')
base=re.sub(r'CREATE OR REPLACE VIEW public\.vw_fgpt_acervo_v3[\s\S]*?WHERE publicado;',lambda m:"DO $view$ BEGIN IF to_regclass('public.vw_fgpt_acervo_v3') IS NULL THEN EXECUTE $definition$"+m.group(0)+"$definition$; END IF; END $view$;",base,count=1)
admin=(root/'sql/v4/admin_re_migration.sql').read_text(encoding='utf-8')
pre="""-- FALHAS GPT V4 — INSTALADOR COMPLETO E TRANSACIONAL
-- Cole inteiro no SQL Editor. Não precisa do antigo SQL 03.
-- Preserva funções V2, procedimentos e usuários existentes.
BEGIN;
DO $$ BEGIN
 IF current_setting('server_version_num')::integer < 150000 THEN RAISE EXCEPTION 'Requer PostgreSQL 15 ou superior.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id='35eadffb-84a8-499c-8a24-bdb0231ef2de') THEN RAISE EXCEPTION 'Administrador não encontrado neste projeto. Nenhuma alteração aplicada. Verifique o UUID em Authentication > Users.'; END IF;
END $$;
"""
end="\nSELECT falhas_gpt.reindexar();\nNOTIFY pgrst,'reload schema';\nCOMMIT;\nSELECT 'V4 instalada: administrador configurado, RE obrigatório e busca preservada.' AS resultado;\n"
(root/'sql/v4/01_INSTALAR_ATUALIZACAO_V4.sql').write_text(pre+base+'\n'+admin+end,encoding='utf-8')
print('Instalador V4 gerado.')
