from pathlib import Path
root=Path(__file__).resolve().parents[1]
base=(root/'sql/01_instalar_motor_busca.sql').read_text(encoding='utf-8')
v4=(root/'sql/v4/admin_re_migration.sql').read_text(encoding='utf-8')
fragment=(root/'sql/v5/migration.sql').read_text(encoding='utf-8')
def between(text,start,end): return text[text.index(start):text.index(end)]
indexer=between(base,'CREATE OR REPLACE FUNCTION falhas_gpt.indexar_procedimento()', 'CREATE OR REPLACE FUNCTION falhas_gpt.marcar_atualizacao()')
indexer=indexer.replace('  INSERT INTO falhas_gpt.termos_busca','  IF NEW.excluido_em IS NOT NULL THEN RETURN NEW; END IF;\n  INSERT INTO falhas_gpt.termos_busca')
indexer=indexer.replace("      UNION ALL SELECT 'contexto',concat_ws(' ',NEW.topico,NEW.categoria,NEW.serie)","      UNION ALL SELECT 'contexto',concat_ws(' ',NEW.topico,NEW.categoria,NEW.serie)\n      UNION ALL SELECT 'resumo',substring(NEW.resumo FROM pos FOR 480) FROM generate_series(1,length(NEW.resumo),360) pos\n      UNION ALL SELECT 'conteudo',substring(NEW.procedimento_completo FROM pos FOR 480) FROM generate_series(1,length(NEW.procedimento_completo),360) pos")
scoring=between(base,'CREATE OR REPLACE FUNCTION falhas_gpt.pontuar(', '-- View compatível')
scoring=scoring.replace(" IF origem='contexto' THEN valor:=least(valor,85); END IF;", " IF origem='contexto' THEN valor:=least(valor,85); END IF;\n IF origem='resumo' THEN valor:=least(valor,82); motivo:='ocorrência no resumo; '||motivo; END IF;\n IF origem='conteudo' THEN valor:=least(valor,78); motivo:='ocorrência no conteúdo completo; '||motivo; END IF;")
search=between(base,'DO $do$ DECLARE ns text; body text; BEGIN','CREATE OR REPLACE FUNCTION public.status_fgpt_v3()')
search=search.replace('WHERE p.publicado AND (','WHERE p.publicado AND p.excluido_em IS NULL AND (')
search=search.replace('OR t.documento @@ busca_ts OR t.tokens && qt', 'OR t.documento @@ busca_ts OR t.tokens && qt\n       OR (t.origem IN (\'resumo\',\'conteudo\') AND __TRGM__.word_similarity(qc,t.canonico)>=0.25::real)')
search=search.replace('OR EXISTS (SELECT 1 FROM unnest(qt)',"OR (t.origem NOT IN ('resumo','conteudo') AND EXISTS (SELECT 1 FROM unnest(qt)")
search=search.replace('falhas_gpt.proximidade_palavra(a,b)>=0.6)', 'falhas_gpt.proximidade_palavra(a,b)>=0.6))')
search=search.replace('t.tokens,t.origem,t.titulo_tokens)',"t.tokens,t.origem,CASE WHEN t.origem IN ('resumo','conteudo') THEN t.tokens ELSE t.titulo_tokens END)")
search=search.replace('WHERE id=p_id AND publicado)', 'WHERE id=p_id AND publicado AND excluido_em IS NULL)')
search=search.replace('AND p.publicado)', 'AND p.publicado AND p.excluido_em IS NULL)')
admin=between(v4,'CREATE OR REPLACE FUNCTION public.fgpt_admin_salvar_procedimento_v4(', 'CREATE OR REPLACE FUNCTION public.fgpt_anexos_v4(')
admin=admin.replace('WHERE id=x)', 'WHERE id=x AND excluido_em IS NULL)').replace('WHERE id=p_id FOR UPDATE;', 'WHERE id=p_id AND excluido_em IS NULL FOR UPDATE;').replace('p WHERE id=p_id;', 'p WHERE id=p_id AND excluido_em IS NULL;')
old="WHERE topico ILIKE '%'||left(coalesce(p_busca,''),200)||'%' OR codigo ILIKE '%'||left(coalesce(p_busca,''),200)||'%'"
admin=admin.replace(old,"WHERE excluido_em IS NULL AND (topico ILIKE '%'||left(coalesce(p_busca,''),200)||'%' OR codigo ILIKE '%'||left(coalesce(p_busca,''),200)||'%')")
parts={'-- {{INDEXER}}':indexer,'-- {{SCORING}}':scoring,'-- {{SEARCH}}':search,'-- {{ADMIN}}':admin}
for marker,value in parts.items(): fragment=fragment.replace(marker,value)
(root/'sql/v5/04_ATUALIZAR_V4_PARA_V5.sql').write_text(fragment,encoding='utf-8')
print('SQL incremental V5 gerado.')
