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

CREATE OR REPLACE FUNCTION falhas_gpt.indexar_procedimento()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog
AS $$ BEGIN
  DELETE FROM falhas_gpt.termos_busca WHERE procedimento_id=NEW.id;
  IF NEW.excluido_em IS NOT NULL THEN RETURN NEW; END IF;
  INSERT INTO falhas_gpt.termos_busca(procedimento_id,origem,termo,normalizado,canonico,tokens,documento)
  SELECT NEW.id,origem,termo,normalizado,canonico,falhas_gpt.tokens(canonico),to_tsvector('portuguese',canonico)
  FROM (
    SELECT origem,termo,falhas_gpt.normalizar(termo) normalizado,falhas_gpt.canonizar(termo) canonico
    FROM (
      SELECT 'titulo'::text origem,NEW.topico termo
      UNION ALL SELECT 'alias',unnest(NEW.aliases)
      UNION ALL SELECT 'palavra_chave',unnest(NEW.palavras_chave)
      UNION ALL SELECT 'contexto',concat_ws(' ',NEW.topico,NEW.categoria,NEW.serie)
      UNION ALL SELECT 'resumo',substring(NEW.resumo FROM pos FOR 480) FROM generate_series(1,length(NEW.resumo),360) pos
      UNION ALL SELECT 'conteudo',substring(NEW.procedimento_completo FROM pos FOR 480) FROM generate_series(1,length(NEW.procedimento_completo),360) pos
    ) frases WHERE length(trim(termo)) BETWEEN 2 AND 500
  ) n WHERE normalizado <> '' ON CONFLICT DO NOTHING;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS fgpt_indexar_v3 ON falhas_gpt.procedimentos;
CREATE TRIGGER fgpt_indexar_v3 AFTER INSERT OR UPDATE OF topico,categoria,serie,aliases,palavras_chave,resumo,procedimento_completo,excluido_em ON falhas_gpt.procedimentos
 FOR EACH ROW EXECUTE FUNCTION falhas_gpt.indexar_procedimento();
CREATE OR REPLACE FUNCTION falhas_gpt.reindexar()
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$ UPDATE falhas_gpt.procedimentos SET topico=topico WHERE excluido_em IS NULL $$;
CREATE OR REPLACE FUNCTION falhas_gpt.pontuar(
 qnorm text,qcanon text,qt text[],pnorm text,pcanon text,pt text[],origem text,titulo_tokens text[])
RETURNS TABLE(pontos numeric,motivo text)
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE SET search_path=pg_catalog
AS $$ DECLARE cobertura double precision; similaridade double precision; valor double precision;
 oposto boolean; negacao_diferente boolean; informativos integer;
BEGIN
 SELECT count(*) INTO informativos FROM unnest(qt) x WHERE x NOT IN ('nao','sem','nunca');
 IF informativos=0 OR cardinality(pt)=0 THEN RETURN QUERY SELECT 0::numeric,'sem termos úteis'::text; RETURN; END IF;
 SELECT avg(coalesce((SELECT max(falhas_gpt.proximidade_palavra(a,b)) FROM unnest(pt) b),0))
 INTO cobertura FROM unnest(qt) a WHERE a NOT IN ('nao','sem','nunca');
 similaridade:=falhas_gpt.sim(qcanon,pcanon);
 oposto:=('abre'=ANY(qt) AND 'fecha'=ANY(titulo_tokens) AND NOT 'abre'=ANY(titulo_tokens))
       OR ('fecha'=ANY(qt) AND 'abre'=ANY(titulo_tokens) AND NOT 'fecha'=ANY(titulo_tokens));
 negacao_diferente:=((qt && ARRAY['nao','sem','nunca']) <> (titulo_tokens && ARRAY['nao','sem','nunca']))
   AND qt && ARRAY['nao','sem','nunca','abre','fecha'];
 IF qnorm=pnorm THEN
   valor:=CASE origem WHEN 'titulo' THEN 100 WHEN 'alias' THEN 98 ELSE 91 END; motivo:='correspondência exata: '||origem;
 ELSIF qcanon=pcanon THEN
   valor:=CASE origem WHEN 'titulo' THEN 96 WHEN 'alias' THEN 95 ELSE 89 END; motivo:='expressão equivalente: '||origem;
 ELSIF qt=pt THEN valor:=93; motivo:='mesmos termos em outra forma ou ordem';
 ELSIF qt <@ pt THEN valor:=86+4.0*cardinality(qt)/greatest(cardinality(pt),1); motivo:='todos os termos encontrados';
 ELSIF cobertura>=0.65 THEN valor:=least(88,45+30*cobertura+13*similaridade); motivo:='palavras próximas ou erro de digitação';
 ELSIF cobertura>=0.30 THEN valor:=least(68,20+30*cobertura+18*similaridade); motivo:='correspondência parcial';
 ELSE valor:=0; motivo:='sem correspondência suficiente'; END IF;
 IF negacao_diferente THEN valor:=greatest(0,valor-30); motivo:=motivo||'; negação diferente'; END IF;
 IF oposto THEN valor:=least(44,greatest(0,valor-12)); motivo:=motivo||'; ação diferente'; END IF;
 IF origem='palavra_chave' THEN valor:=least(valor,72); END IF;
 IF origem='contexto' THEN valor:=least(valor,85); END IF;
 IF origem='resumo' THEN valor:=least(valor,82); motivo:='ocorrência no resumo; '||motivo; END IF;
 IF origem='conteudo' THEN valor:=least(valor,78); motivo:='ocorrência no conteúdo completo; '||motivo; END IF;
 RETURN QUERY SELECT round(greatest(0,least(100,valor))::numeric,2),motivo;
END $$;


DO $do$ DECLARE ns text; body text; BEGIN
 SELECT n.nspname INTO ns FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace WHERE e.extname='pg_trgm';
 body := $fn$
 CREATE OR REPLACE FUNCTION public.buscar_fgpt_v3(p_busca text,p_limite integer DEFAULT 10,p_minimo numeric DEFAULT 25)
 RETURNS TABLE(id uuid,topico text,categoria text,tipo text,serie text,resumo text,procedimento_completo text,
   aliases text[],relacionados uuid[],fonte text,revisao text,exemplo boolean,relevancia numeric,origem_match text,termo_encontrado text)
 LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog
 AS $search$
 DECLARE qn text; qc text; qt text[]; busca_ts tsquery;
 BEGIN
   IF NOT falhas_gpt.pode_ler() THEN RAISE EXCEPTION 'Usuário sem acesso ao acervo Falhas GPT.' USING ERRCODE='42501'; END IF;
   IF length(coalesce(p_busca,''))>200 THEN RAISE EXCEPTION 'A consulta deve ter até 200 caracteres.' USING ERRCODE='22023'; END IF;
   qn:=falhas_gpt.normalizar(p_busca); qc:=falhas_gpt.canonizar(p_busca); qt:=falhas_gpt.tokens(qc);
   IF length(qn)<2 OR cardinality(qt)=0 OR NOT EXISTS(SELECT 1 FROM unnest(qt) x WHERE x NOT IN ('nao','sem','nunca')) THEN RETURN; END IF;
   SELECT to_tsquery('portuguese',string_agg(x,' | ')) INTO busca_ts FROM unnest(qt) x WHERE x NOT IN ('nao','sem','nunca');
   RETURN QUERY
   WITH candidatos AS MATERIALIZED (
     SELECT t.*,falhas_gpt.tokens(falhas_gpt.canonizar(p.topico)) titulo_tokens FROM falhas_gpt.termos_busca t JOIN falhas_gpt.procedimentos p ON p.id=t.procedimento_id
     WHERE p.publicado AND p.excluido_em IS NULL AND (
       __TRGM__.similarity(t.normalizado,qn)>=0.15::real OR __TRGM__.similarity(t.canonico,qc)>=0.15::real
       OR t.documento @@ busca_ts OR t.tokens && qt
       OR (t.origem IN ('resumo','conteudo') AND __TRGM__.word_similarity(qc,t.canonico)>=0.25::real)
       OR (t.origem NOT IN ('resumo','conteudo') AND EXISTS (SELECT 1 FROM unnest(qt) a CROSS JOIN unnest(t.tokens) b
         WHERE length(a)>=4 AND length(b)>=4 AND falhas_gpt.proximidade_palavra(a,b)>=0.6))
     )
   ), pontos AS (
     SELECT t.procedimento_id,t.termo,t.origem,s.pontos,s.motivo,
       row_number() OVER(PARTITION BY t.procedimento_id ORDER BY s.pontos DESC,
         CASE t.origem WHEN 'titulo' THEN 1 WHEN 'alias' THEN 2 WHEN 'contexto' THEN 3 ELSE 4 END,t.normalizado) rn
     FROM candidatos t CROSS JOIN LATERAL falhas_gpt.pontuar(qn,qc,qt,t.normalizado,t.canonico,t.tokens,t.origem,CASE WHEN t.origem IN ('resumo','conteudo') THEN t.tokens ELSE t.titulo_tokens END) s
   )
   SELECT p.id,p.topico,p.categoria,p.tipo,p.serie,p.resumo,p.procedimento_completo,p.aliases,p.relacionados,
     p.fonte,p.revisao,p.exemplo,r.pontos,r.motivo,r.termo
   FROM pontos r JOIN falhas_gpt.procedimentos p ON p.id=r.procedimento_id
   WHERE r.rn=1 AND r.pontos>=greatest(1,least(100,coalesce(p_minimo,25)))
   ORDER BY r.pontos DESC,p.topico,p.id LIMIT greatest(1,least(50,coalesce(p_limite,10)));
 END $search$;
 $fn$;
 EXECUTE replace(body,'__TRGM__',quote_ident(ns));
END $do$;

CREATE OR REPLACE FUNCTION public.relacionados_fgpt_v3(p_id uuid,p_limite integer DEFAULT 5)
RETURNS TABLE(id uuid,topico text,categoria text,tipo text,resumo text,exemplo boolean,relevancia numeric,origem_match text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 WITH origem AS (SELECT * FROM falhas_gpt.procedimentos WHERE id=p_id AND publicado AND excluido_em IS NULL),
 pontuados AS (
 SELECT p.id,p.topico,p.categoria,p.tipo,p.resumo,p.exemplo,
 CASE WHEN p.id=ANY(o.relacionados) THEN 100::numeric
 ELSE least(89, (CASE WHEN p.categoria=o.categoria THEN 35 ELSE 0 END)
   + falhas_gpt.sim(falhas_gpt.normalizar(o.topico),falhas_gpt.normalizar(p.topico))*45
   + (CASE WHEN p.palavras_chave && o.palavras_chave THEN 15 ELSE 0 END))::numeric END score,
 CASE WHEN p.id=ANY(o.relacionados) THEN 'relação cadastrada' ELSE 'proximidade de tópico e categoria' END motivo
 FROM origem o JOIN falhas_gpt.procedimentos p ON p.id<>o.id AND p.publicado AND p.excluido_em IS NULL)
 SELECT id,topico,categoria,tipo,resumo,exemplo,round(score,2),motivo FROM pontuados WHERE score>=25
 ORDER BY score DESC,topico,id LIMIT greatest(1,least(20,coalesce(p_limite,5))) $$;

CREATE OR REPLACE FUNCTION public.fgpt_admin_salvar_procedimento_v4(p_dados jsonb,p_id uuid DEFAULT NULL,p_versao integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v falhas_gpt.procedimentos%ROWTYPE; n bigint; v_alias text[]; v_palavras text[]; v_rel uuid[]; k text; pub boolean;
BEGIN
 PERFORM falhas_gpt.exigir_admin();
 IF p_dados IS NULL OR jsonb_typeof(p_dados)<>'object' THEN RAISE EXCEPTION 'Preencha o procedimento.'; END IF;
 IF length(trim(coalesce(p_dados->>'topico',''))) NOT BETWEEN 2 AND 250 THEN RAISE EXCEPTION 'Título: use entre 2 e 250 caracteres.'; END IF;
 IF coalesce(p_dados->>'tipo','') NOT IN ('procedimento','restabelecimento') THEN RAISE EXCEPTION 'Selecione o tipo do registro.'; END IF;
 pub:=coalesce((p_dados->>'publicado')::boolean,false);
 FOREACH k IN ARRAY ARRAY['categoria','serie','fonte','revisao','numero_documento'] LOOP
  IF length(coalesce(p_dados->>k,''))>250 THEN RAISE EXCEPTION 'Campo % excede 250 caracteres.',k; END IF;
 END LOOP;
 IF length(coalesce(p_dados->>'resumo',''))>6000 OR length(coalesce(p_dados->>'procedimento_completo',''))>2000000 THEN RAISE EXCEPTION 'Resumo ou texto completo excedeu o limite.'; END IF;
 IF pub THEN
  FOREACH k IN ARRAY ARRAY['categoria','serie','resumo','procedimento_completo','fonte','revisao'] LOOP
   IF trim(coalesce(p_dados->>k,''))='' THEN RAISE EXCEPTION 'Para disponibilizar o procedimento, preencha: %.',k; END IF;
  END LOOP;
 END IF;
 IF jsonb_typeof(coalesce(p_dados->'aliases','[]'::jsonb))<>'array' OR jsonb_typeof(coalesce(p_dados->'palavras_chave','[]'::jsonb))<>'array' OR jsonb_typeof(coalesce(p_dados->'relacionados','[]'::jsonb))<>'array' THEN RAISE EXCEPTION 'Termos e relações devem ser listas.'; END IF;
 SELECT coalesce(array_agg(DISTINCT trim(x)) FILTER(WHERE trim(x)<>''),'{}') INTO v_alias FROM jsonb_array_elements_text(coalesce(p_dados->'aliases','[]')) x;
 SELECT coalesce(array_agg(DISTINCT trim(x)) FILTER(WHERE trim(x)<>''),'{}') INTO v_palavras FROM jsonb_array_elements_text(coalesce(p_dados->'palavras_chave','[]')) x;
 SELECT coalesce(array_agg(DISTINCT x::uuid),'{}') INTO v_rel FROM jsonb_array_elements_text(coalesce(p_dados->'relacionados','[]')) x;
 IF cardinality(v_alias)>50 OR cardinality(v_palavras)>50 OR cardinality(v_rel)>30 OR EXISTS(SELECT 1 FROM unnest(v_alias||v_palavras) x WHERE length(x)>250) THEN RAISE EXCEPTION 'Máximo: 50 aliases, 50 palavras-chave (250 caracteres cada) e 30 relacionados.'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(v_rel) x WHERE NOT EXISTS(SELECT 1 FROM falhas_gpt.procedimentos WHERE id=x AND excluido_em IS NULL) OR x=p_id) THEN RAISE EXCEPTION 'Há relação inválida ou com o próprio procedimento.'; END IF;
 IF p_id IS NULL THEN
  n:=nextval('falhas_gpt.procedimento_numero_v4');
  INSERT INTO falhas_gpt.procedimentos(codigo,numero_sequencial,topico)
  VALUES('trafego-trens-falhasgptapp-'||lpad(n::text,greatest(2,length(n::text)),'0'),n,trim(p_dados->>'topico')) RETURNING * INTO v;
 ELSE
  SELECT * INTO v FROM falhas_gpt.procedimentos WHERE id=p_id AND excluido_em IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Procedimento não encontrado.'; END IF;
  IF p_versao IS DISTINCT FROM v.versao_edicao THEN RAISE EXCEPTION 'Outro acesso alterou este procedimento. Reabra o registro antes de salvar.' USING ERRCODE='40001'; END IF;
 END IF;
 UPDATE falhas_gpt.procedimentos SET topico=trim(p_dados->>'topico'),categoria=coalesce(nullif(trim(p_dados->>'categoria'),''),'Geral'),tipo=p_dados->>'tipo',
 serie=trim(coalesce(p_dados->>'serie','')),resumo=trim(coalesce(p_dados->>'resumo','')),procedimento_completo=coalesce(p_dados->>'procedimento_completo',''),
 aliases=v_alias,palavras_chave=v_palavras,relacionados=v_rel,fonte=trim(coalesce(p_dados->>'fonte','')),revisao=trim(coalesce(p_dados->>'revisao','')),
 numero_documento=trim(coalesce(p_dados->>'numero_documento','')),publicado=pub,exemplo=false,versao_edicao=CASE WHEN p_id IS NULL THEN 1 ELSE versao_edicao+1 END
 WHERE id=v.id RETURNING * INTO v;
 INSERT INTO falhas_gpt.auditoria(usuario_id,acao,objeto,detalhes) VALUES(auth.uid(),CASE WHEN p_id IS NULL THEN 'criar_procedimento' ELSE 'editar_procedimento' END,v.id::text,jsonb_build_object('codigo',v.codigo,'publicado',pub,'versao',v.versao_edicao));
 RETURN to_jsonb(v);
END $$;
CREATE OR REPLACE FUNCTION public.fgpt_admin_listar_procedimentos_v4(p_busca text DEFAULT '',p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v jsonb;
BEGIN
 PERFORM falhas_gpt.exigir_admin();
 SELECT jsonb_build_object('total',(SELECT count(*) FROM falhas_gpt.procedimentos WHERE excluido_em IS NULL AND (topico ILIKE '%'||left(coalesce(p_busca,''),200)||'%' OR codigo ILIKE '%'||left(coalesce(p_busca,''),200)||'%')),
 'items',coalesce((SELECT jsonb_agg(x) FROM(SELECT id,codigo,numero_sequencial,numero_documento,topico,categoria,tipo,serie,revisao,publicado,exemplo,versao_edicao,atualizado_em
 FROM falhas_gpt.procedimentos WHERE excluido_em IS NULL AND (topico ILIKE '%'||left(coalesce(p_busca,''),200)||'%' OR codigo ILIKE '%'||left(coalesce(p_busca,''),200)||'%')
 ORDER BY atualizado_em DESC,id LIMIT 50 OFFSET greatest(0,coalesce(p_offset,0))) x),'[]'::jsonb)) INTO v;
 RETURN v;
END $$;
CREATE OR REPLACE FUNCTION public.fgpt_admin_obter_procedimento_v4(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v jsonb; BEGIN
 PERFORM falhas_gpt.exigir_admin();
 SELECT to_jsonb(p)||jsonb_build_object('anexos',coalesce((SELECT jsonb_agg(a) FROM falhas_gpt.anexos a WHERE a.procedimento_id=p.id),'[]'::jsonb)) INTO v FROM falhas_gpt.procedimentos p WHERE id=p_id AND excluido_em IS NULL;
 IF v IS NULL THEN RAISE EXCEPTION 'Procedimento não encontrado.'; END IF;
 RETURN v;
END $$;


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
