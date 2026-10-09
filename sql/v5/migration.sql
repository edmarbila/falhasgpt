-- FALHAS GPT V5 — aplicar INTEIRO depois da V4. Preserva usuários, REs e documentos.
-- Reaplicável. Não executar novamente os instaladores V3/V4 depois desta atualização.
-- Correção 2026-10-08: limites explícitos de similaridade, sem SET de parâmetros pg_trgm.
-- Preserva a pontuação e a ordem dos resultados. Não requer GRANT SET ou superusuário.
BEGIN;
DO $$ BEGIN
 IF to_regclass('falhas_gpt.migracoes') IS NULL THEN RAISE EXCEPTION 'Instale a V4 antes da V5.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM falhas_gpt.migracoes WHERE versao=4) THEN RAISE EXCEPTION 'Instale a V4 antes da V5.'; END IF;
END $$;
ALTER TABLE falhas_gpt.procedimentos ADD COLUMN IF NOT EXISTS excluido_em timestamptz;
ALTER TABLE falhas_gpt.termos_busca DROP CONSTRAINT IF EXISTS termos_busca_origem_check;
ALTER TABLE falhas_gpt.termos_busca ADD CONSTRAINT termos_busca_origem_check CHECK(origem IN ('titulo','alias','palavra_chave','contexto','resumo','conteudo'));

-- {{INDEXER}}
DROP TRIGGER IF EXISTS fgpt_indexar_v3 ON falhas_gpt.procedimentos;
CREATE TRIGGER fgpt_indexar_v3 AFTER INSERT OR UPDATE OF topico,categoria,serie,aliases,palavras_chave,resumo,procedimento_completo,excluido_em ON falhas_gpt.procedimentos
 FOR EACH ROW EXECUTE FUNCTION falhas_gpt.indexar_procedimento();
CREATE OR REPLACE FUNCTION falhas_gpt.reindexar()
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$ UPDATE falhas_gpt.procedimentos SET topico=topico WHERE excluido_em IS NULL $$;
-- {{SCORING}}
-- {{SEARCH}}
-- {{ADMIN}}

CREATE OR REPLACE FUNCTION public.fgpt_admin_excluir_procedimento_v5(p_id uuid,p_versao integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v falhas_gpt.procedimentos%ROWTYPE;
BEGIN
 PERFORM falhas_gpt.exigir_admin();
 SELECT * INTO v FROM falhas_gpt.procedimentos WHERE id=p_id AND excluido_em IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Procedimento não encontrado ou já excluído.'; END IF;
 IF p_versao IS DISTINCT FROM v.versao_edicao THEN RAISE EXCEPTION 'Outro acesso alterou este procedimento. Atualize a lista antes de excluir.' USING ERRCODE='40001'; END IF;
 UPDATE falhas_gpt.procedimentos SET excluido_em=now(),publicado=false,versao_edicao=versao_edicao+1 WHERE id=p_id;
 UPDATE falhas_gpt.procedimentos SET relacionados=array_remove(relacionados,p_id),versao_edicao=versao_edicao+1 WHERE p_id=ANY(relacionados) AND excluido_em IS NULL;
 INSERT INTO falhas_gpt.auditoria(usuario_id,acao,objeto,detalhes) VALUES(auth.uid(),'excluir_procedimento',p_id::text,jsonb_build_object('codigo',v.codigo,'titulo',v.topico,'tipo_exclusao','logica'));
 RETURN jsonb_build_object('id',p_id,'codigo',v.codigo,'excluido',true);
END $$;
CREATE OR REPLACE FUNCTION public.fgpt_admin_topicos_v5(p_busca text DEFAULT '',p_selecionados uuid[] DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM falhas_gpt.exigir_admin();
 IF cardinality(p_selecionados)>30 THEN RAISE EXCEPTION 'Selecione até 30 tópicos.'; END IF;
 RETURN (SELECT coalesce(jsonb_agg(x ORDER BY x.topico,x.id),'[]') FROM (
 SELECT id,topico,codigo,categoria,tipo,publicado FROM falhas_gpt.procedimentos WHERE excluido_em IS NULL AND id=ANY(p_selecionados)
 UNION
 (SELECT id,topico,codigo,categoria,tipo,publicado FROM falhas_gpt.procedimentos WHERE excluido_em IS NULL AND (falhas_gpt.normalizar(topico) LIKE '%'||falhas_gpt.normalizar(left(coalesce(p_busca,''),200))||'%' OR codigo ILIKE '%'||left(coalesce(p_busca,''),200)||'%') ORDER BY topico,id LIMIT 50)
 ) x);
END $$;
CREATE OR REPLACE FUNCTION public.fgpt_admin_criar_topico_v5(p_titulo text,p_tipo text DEFAULT 'procedimento',p_categoria text DEFAULT 'Geral',p_serie text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v jsonb;
BEGIN
 PERFORM falhas_gpt.exigir_admin();
 IF length(trim(coalesce(p_titulo,''))) NOT BETWEEN 2 AND 250 THEN RAISE EXCEPTION 'Título: use entre 2 e 250 caracteres.'; END IF;
 IF p_tipo NOT IN ('procedimento','restabelecimento') OR p_tipo IS NULL THEN RAISE EXCEPTION 'Tipo inválido.'; END IF;
 PERFORM pg_advisory_xact_lock(hashtext('fgpt_topico:'||falhas_gpt.normalizar(p_titulo)||':'||p_tipo));
 SELECT to_jsonb(p) INTO v FROM falhas_gpt.procedimentos p WHERE excluido_em IS NULL AND falhas_gpt.normalizar(topico)=falhas_gpt.normalizar(p_titulo) AND tipo=p_tipo ORDER BY criado_em,id LIMIT 1;
 IF v IS NOT NULL THEN RETURN jsonb_build_object('item',v,'existente',true); END IF;
 v:=public.fgpt_admin_salvar_procedimento_v4(jsonb_build_object('topico',trim(p_titulo),'tipo',p_tipo,'categoria',p_categoria,'serie',p_serie,'publicado',false));
 RETURN jsonb_build_object('item',v,'existente',false);
END $$;

DROP POLICY IF EXISTS fgpt_ler_procedimentos_v3 ON falhas_gpt.procedimentos;
CREATE POLICY fgpt_ler_procedimentos_v3 ON falhas_gpt.procedimentos FOR SELECT TO authenticated
 USING(excluido_em IS NULL AND ((publicado AND (SELECT falhas_gpt.pode_ler())) OR (SELECT falhas_gpt.e_admin())));
CREATE OR REPLACE VIEW public.vw_fgpt_acervo_v3 WITH(security_invoker=true) AS
 SELECT id,codigo,topico,categoria,tipo,serie,resumo,procedimento_completo,aliases,palavras_chave,relacionados,fonte,revisao,exemplo,atualizado_em,numero_sequencial,numero_documento
 FROM falhas_gpt.procedimentos WHERE publicado AND excluido_em IS NULL;
CREATE OR REPLACE FUNCTION public.fgpt_sessao_v4()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('versao',5,'usuario_id',auth.uid(),'autorizado',falhas_gpt.pode_ler(),
 'admin',falhas_gpt.e_admin(),'nome',coalesce((SELECT nome FROM falhas_gpt.perfis WHERE usuario_id=auth.uid()),'Administrador'),
 're',(SELECT re FROM falhas_gpt.perfis WHERE usuario_id=auth.uid()))
$$;
REVOKE ALL ON FUNCTION public.fgpt_admin_excluir_procedimento_v5(uuid,integer),public.fgpt_admin_topicos_v5(text,uuid[]),public.fgpt_admin_criar_topico_v5(text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fgpt_admin_excluir_procedimento_v5(uuid,integer),public.fgpt_admin_topicos_v5(text,uuid[]),public.fgpt_admin_criar_topico_v5(text,text,text,text) TO authenticated;
-- Textos existentes são reindexados, inclusive conteúdo importado de PDF. Nenhum texto é alterado.
SELECT falhas_gpt.reindexar();
INSERT INTO falhas_gpt.migracoes(versao) VALUES(5) ON CONFLICT DO NOTHING;
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'V5 corrigida instalada: busca sem SET pg_trgm, conteúdo completo, exclusão administrativa e criação de tópicos.' AS resultado;
