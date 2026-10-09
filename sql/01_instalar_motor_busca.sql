-- FALHAS GPT · MOTOR DE BUSCA V3 · PostgreSQL 15+ / Supabase
-- Execute inteiro no SQL Editor. Aditivo: não altera buscar_fgpt_v2 nem importa acervo antigo.
-- Privacidade: somente usuários autenticados e cadastrados em falhas_gpt.acessos leem o acervo.
-- Nenhum procedimento operacional é inventado por este script.
BEGIN;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch WITH SCHEMA extensions;
CREATE SCHEMA IF NOT EXISTS falhas_gpt;
REVOKE ALL ON SCHEMA falhas_gpt FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA falhas_gpt TO authenticated;

CREATE TABLE IF NOT EXISTS falhas_gpt.acessos (
  usuario_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  criado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE falhas_gpt.acessos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fgpt_acesso_proprio_v3 ON falhas_gpt.acessos;
CREATE POLICY fgpt_acesso_proprio_v3 ON falhas_gpt.acessos FOR SELECT TO authenticated
  USING (usuario_id = (SELECT auth.uid()));
GRANT SELECT ON falhas_gpt.acessos TO authenticated;

CREATE OR REPLACE FUNCTION falhas_gpt.pode_ler()
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = pg_catalog
AS $$ SELECT current_user IN ('postgres','supabase_admin','service_role')
  OR EXISTS (SELECT 1 FROM falhas_gpt.acessos WHERE usuario_id = (SELECT auth.uid())) $$;

CREATE OR REPLACE FUNCTION falhas_gpt.normalizar(p_texto text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path = pg_catalog
AS $$ SELECT trim(regexp_replace(regexp_replace(
  translate(lower(coalesce(p_texto,'')),
  'áàâãäåéèêëíìîïóòôõöúùûüçñýÿ',
  'aaaaaaeeeeiiiiooooouuuucnyy'), '[^a-z0-9 ]',' ','g'), '\s+',' ','g')) $$;

CREATE OR REPLACE FUNCTION falhas_gpt.tokens(p_texto text)
RETURNS text[] LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path = pg_catalog
AS $$ SELECT coalesce(array_agg(DISTINCT t ORDER BY t), ARRAY[]::text[])
  FROM regexp_split_to_table(falhas_gpt.normalizar(p_texto),' ') t
  WHERE t <> '' AND t <> ALL (ARRAY['a','o','as','os','de','da','do','das','dos','e','um','uma',
  'para','por','com','em','no','na','nos','nas','ao','aos','eu','me','meu','minha','que','qual',
  'como','favor','porfavor','preciso','quero','pode','poderia','realizar','fazer','procedimento',
  'procedimentos','esta','estao','estou','trem','trens','sistema']) $$;

-- As equivalências são editáveis: inclua termos realmente equivalentes para seu acervo.
CREATE TABLE IF NOT EXISTS falhas_gpt.sinonimos (
  termo text PRIMARY KEY CHECK (termo = falhas_gpt.normalizar(termo) AND termo <> ''),
  equivalente text NOT NULL CHECK (equivalente = falhas_gpt.normalizar(equivalente) AND equivalente <> ''),
  CHECK (termo <> equivalente)
);
INSERT INTO falhas_gpt.sinonimos(termo,equivalente) VALUES
 ('portas','porta'),('abrindo','abre'),('abrir','abre'),('abertura','abre'),
 ('fechando','fecha'),('fechar','fecha'),('fechamento','fecha'),
 ('isolar','isolamento'),('isolada','isolamento'),('isolado','isolamento'),
 ('restabelecer','restabelecimento'),('restabelecimentos','restabelecimento'),
 ('nao consegue abrir','nao abre'),('nao consegue fechar','nao fecha'),
 ('nao esta abrindo','nao abre'),('nao esta fechando','nao fecha'),
 ('falha de abertura','nao abre'),('falha de fechamento','nao fecha')
ON CONFLICT (termo) DO NOTHING;

CREATE OR REPLACE FUNCTION falhas_gpt.canonizar(p_texto text)
RETURNS text LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = pg_catalog
AS $$ DECLARE v text := ' ' || falhas_gpt.normalizar(p_texto) || ' '; r record;
BEGIN
  -- Uma passagem ordenada por expressão mais longa. Não interpreta nem executa instruções.
  FOR r IN SELECT termo,equivalente FROM falhas_gpt.sinonimos ORDER BY length(termo) DESC,termo LOOP
    v := regexp_replace(v,'\m' || r.termo || '\M',r.equivalente,'g');
  END LOOP;
  RETURN trim(regexp_replace(v,'\s+',' ','g'));
END $$;

-- Usa o schema no qual pg_trgm já está instalado, sem mover extensões existentes.
DO $do$ DECLARE ns text;
BEGIN
 SELECT n.nspname INTO ns FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace WHERE e.extname='pg_trgm';
 EXECUTE format('GRANT USAGE ON SCHEMA %I TO authenticated',ns);
 EXECUTE format('CREATE OR REPLACE FUNCTION falhas_gpt.sim(text,text) RETURNS real LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path=pg_catalog AS %L',
   format('SELECT %I.similarity($1,$2)',ns));
END $do$;
DO $do$ DECLARE ns text; BEGIN
 SELECT n.nspname INTO ns FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace WHERE e.extname='fuzzystrmatch';
 EXECUTE format('GRANT USAGE ON SCHEMA %I TO authenticated',ns);
 EXECUTE format('CREATE OR REPLACE FUNCTION falhas_gpt.distancia(text,text) RETURNS integer LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path=pg_catalog AS %L',
   format('SELECT %I.levenshtein_less_equal(left($1,60),left($2,60),2)',ns));
END $do$;
CREATE OR REPLACE FUNCTION falhas_gpt.proximidade_palavra(a text,b text)
RETURNS double precision LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path=pg_catalog AS $$
 SELECT CASE WHEN a=b THEN 1.0 WHEN least(length(a),length(b))<4 THEN 0.0
 ELSE greatest(CASE WHEN falhas_gpt.sim(a,b)>=0.40 THEN falhas_gpt.sim(a,b)::double precision ELSE 0.0 END,
  CASE WHEN abs(length(a)-length(b))<=2 AND falhas_gpt.distancia(a,b)<=2
   THEN greatest(0.50,1.0-falhas_gpt.distancia(a,b)::double precision/greatest(length(a),length(b))) ELSE 0.0 END) END $$;

CREATE TABLE IF NOT EXISTS falhas_gpt.procedimentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo text UNIQUE NOT NULL CHECK (length(codigo) BETWEEN 1 AND 80),
  topico text NOT NULL CHECK (length(trim(topico)) BETWEEN 2 AND 250),
  categoria text NOT NULL DEFAULT 'Geral',
  tipo text NOT NULL DEFAULT 'procedimento' CHECK (tipo IN ('procedimento','restabelecimento')),
  serie text NOT NULL DEFAULT '',
  resumo text NOT NULL DEFAULT '',
  procedimento_completo text NOT NULL DEFAULT '',
  aliases text[] NOT NULL DEFAULT '{}',
  palavras_chave text[] NOT NULL DEFAULT '{}',
  relacionados uuid[] NOT NULL DEFAULT '{}',
  fonte text NOT NULL DEFAULT '',
  revisao text NOT NULL DEFAULT '',
  publicado boolean NOT NULL DEFAULT false,
  exemplo boolean NOT NULL DEFAULT false,
  criado_em timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  CHECK (cardinality(aliases) <= 50 AND cardinality(palavras_chave) <= 50),
  CHECK (NOT publicado OR exemplo OR (length(trim(resumo)) > 0 AND length(trim(procedimento_completo)) > 0))
);
CREATE TABLE IF NOT EXISTS falhas_gpt.termos_busca (
  procedimento_id uuid NOT NULL REFERENCES falhas_gpt.procedimentos(id) ON DELETE CASCADE,
  origem text NOT NULL CHECK (origem IN ('titulo','alias','palavra_chave','contexto')),
  termo text NOT NULL,
  normalizado text NOT NULL,
  canonico text NOT NULL,
  tokens text[] NOT NULL,
  documento tsvector NOT NULL,
  PRIMARY KEY (procedimento_id,origem,normalizado)
);
CREATE INDEX IF NOT EXISTS fgpt_documento_v3 ON falhas_gpt.termos_busca USING gin(documento);
CREATE INDEX IF NOT EXISTS fgpt_termos_tokens_v3 ON falhas_gpt.termos_busca USING gin(tokens);
CREATE INDEX IF NOT EXISTS fgpt_categoria_v3 ON falhas_gpt.procedimentos(categoria,tipo) WHERE publicado;
DO $do$ DECLARE ns text; BEGIN
 SELECT n.nspname INTO ns FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace WHERE e.extname='pg_trgm';
 EXECUTE format('CREATE INDEX IF NOT EXISTS fgpt_termo_trgm_v3 ON falhas_gpt.termos_busca USING gin(normalizado %I.gin_trgm_ops)',ns);
 EXECUTE format('CREATE INDEX IF NOT EXISTS fgpt_canonico_trgm_v3 ON falhas_gpt.termos_busca USING gin(canonico %I.gin_trgm_ops)',ns);
END $do$;

CREATE OR REPLACE FUNCTION falhas_gpt.indexar_procedimento()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog
AS $$ BEGIN
  DELETE FROM falhas_gpt.termos_busca WHERE procedimento_id=NEW.id;
  INSERT INTO falhas_gpt.termos_busca(procedimento_id,origem,termo,normalizado,canonico,tokens,documento)
  SELECT NEW.id,origem,termo,normalizado,canonico,falhas_gpt.tokens(canonico),to_tsvector('portuguese',canonico)
  FROM (
    SELECT origem,termo,falhas_gpt.normalizar(termo) normalizado,falhas_gpt.canonizar(termo) canonico
    FROM (
      SELECT 'titulo'::text origem,NEW.topico termo
      UNION ALL SELECT 'alias',unnest(NEW.aliases)
      UNION ALL SELECT 'palavra_chave',unnest(NEW.palavras_chave)
      UNION ALL SELECT 'contexto',concat_ws(' ',NEW.topico,NEW.categoria,NEW.serie)
    ) frases WHERE length(trim(termo)) BETWEEN 2 AND 500
  ) n WHERE normalizado <> '' ON CONFLICT DO NOTHING;
  RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION falhas_gpt.marcar_atualizacao()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$ BEGIN NEW.atualizado_em=now(); RETURN NEW; END $$;
DROP TRIGGER IF EXISTS fgpt_atualizado_v3 ON falhas_gpt.procedimentos;
CREATE TRIGGER fgpt_atualizado_v3 BEFORE UPDATE ON falhas_gpt.procedimentos FOR EACH ROW EXECUTE FUNCTION falhas_gpt.marcar_atualizacao();
DROP TRIGGER IF EXISTS fgpt_indexar_v3 ON falhas_gpt.procedimentos;
CREATE TRIGGER fgpt_indexar_v3 AFTER INSERT OR UPDATE OF topico,categoria,serie,aliases,palavras_chave ON falhas_gpt.procedimentos
 FOR EACH ROW EXECUTE FUNCTION falhas_gpt.indexar_procedimento();
CREATE OR REPLACE FUNCTION falhas_gpt.reindexar()
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$ UPDATE falhas_gpt.procedimentos SET topico=topico $$;
CREATE OR REPLACE FUNCTION falhas_gpt.sinonimos_alterados()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$ BEGIN PERFORM falhas_gpt.reindexar(); RETURN NULL; END $$;
DROP TRIGGER IF EXISTS fgpt_sinonimos_v3 ON falhas_gpt.sinonimos;
CREATE TRIGGER fgpt_sinonimos_v3 AFTER INSERT OR UPDATE OR DELETE ON falhas_gpt.sinonimos
 FOR EACH STATEMENT EXECUTE FUNCTION falhas_gpt.sinonimos_alterados();

ALTER TABLE falhas_gpt.procedimentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE falhas_gpt.termos_busca ENABLE ROW LEVEL SECURITY;
ALTER TABLE falhas_gpt.sinonimos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fgpt_ler_procedimentos_v3 ON falhas_gpt.procedimentos;
CREATE POLICY fgpt_ler_procedimentos_v3 ON falhas_gpt.procedimentos FOR SELECT TO authenticated
 USING (publicado AND (SELECT falhas_gpt.pode_ler()));
DROP POLICY IF EXISTS fgpt_ler_termos_v3 ON falhas_gpt.termos_busca;
CREATE POLICY fgpt_ler_termos_v3 ON falhas_gpt.termos_busca FOR SELECT TO authenticated
 USING ((SELECT falhas_gpt.pode_ler()) AND EXISTS (SELECT 1 FROM falhas_gpt.procedimentos p WHERE p.id=procedimento_id));
DROP POLICY IF EXISTS fgpt_ler_sinonimos_v3 ON falhas_gpt.sinonimos;
CREATE POLICY fgpt_ler_sinonimos_v3 ON falhas_gpt.sinonimos FOR SELECT TO authenticated USING ((SELECT falhas_gpt.pode_ler()));
REVOKE ALL ON ALL TABLES IN SCHEMA falhas_gpt FROM anon,authenticated;
GRANT SELECT ON falhas_gpt.acessos,falhas_gpt.procedimentos,falhas_gpt.termos_busca,falhas_gpt.sinonimos TO authenticated;

-- Pontuação por frase. Negações e ações opostas são mantidas no cálculo.
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
 RETURN QUERY SELECT round(greatest(0,least(100,valor))::numeric,2),motivo;
END $$;

-- View compatível com o site. security_invoker preserva as políticas das tabelas.
CREATE OR REPLACE VIEW public.vw_fgpt_acervo_v3 WITH (security_invoker=true) AS
 SELECT id,codigo,topico,categoria,tipo,serie,resumo,procedimento_completo,aliases,palavras_chave,
 relacionados,fonte,revisao,exemplo,atualizado_em FROM falhas_gpt.procedimentos WHERE publicado;
REVOKE ALL ON public.vw_fgpt_acervo_v3 FROM PUBLIC,anon;
GRANT SELECT ON public.vw_fgpt_acervo_v3 TO authenticated;

-- Limites explícitos: não altera parâmetros de sessão pg_trgm nem exige permissão para SET.
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
     WHERE p.publicado AND (
       __TRGM__.similarity(t.normalizado,qn)>=0.15::real OR __TRGM__.similarity(t.canonico,qc)>=0.15::real
       OR t.documento @@ busca_ts OR t.tokens && qt
       OR EXISTS (SELECT 1 FROM unnest(qt) a CROSS JOIN unnest(t.tokens) b
         WHERE length(a)>=4 AND length(b)>=4 AND falhas_gpt.proximidade_palavra(a,b)>=0.6)
     )
   ), pontos AS (
     SELECT t.procedimento_id,t.termo,t.origem,s.pontos,s.motivo,
       row_number() OVER(PARTITION BY t.procedimento_id ORDER BY s.pontos DESC,
         CASE t.origem WHEN 'titulo' THEN 1 WHEN 'alias' THEN 2 WHEN 'contexto' THEN 3 ELSE 4 END,t.normalizado) rn
     FROM candidatos t CROSS JOIN LATERAL falhas_gpt.pontuar(qn,qc,qt,t.normalizado,t.canonico,t.tokens,t.origem,t.titulo_tokens) s
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
 WITH origem AS (SELECT * FROM falhas_gpt.procedimentos WHERE id=p_id AND publicado),
 pontuados AS (
 SELECT p.id,p.topico,p.categoria,p.tipo,p.resumo,p.exemplo,
 CASE WHEN p.id=ANY(o.relacionados) THEN 100::numeric
 ELSE least(89, (CASE WHEN p.categoria=o.categoria THEN 35 ELSE 0 END)
   + falhas_gpt.sim(falhas_gpt.normalizar(o.topico),falhas_gpt.normalizar(p.topico))*45
   + (CASE WHEN p.palavras_chave && o.palavras_chave THEN 15 ELSE 0 END))::numeric END score,
 CASE WHEN p.id=ANY(o.relacionados) THEN 'relação cadastrada' ELSE 'proximidade de tópico e categoria' END motivo
 FROM origem o JOIN falhas_gpt.procedimentos p ON p.id<>o.id AND p.publicado)
 SELECT id,topico,categoria,tipo,resumo,exemplo,round(score,2),motivo FROM pontuados WHERE score>=25
 ORDER BY score DESC,topico,id LIMIT greatest(1,least(20,coalesce(p_limite,5))) $$;
CREATE OR REPLACE FUNCTION public.status_fgpt_v3()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('versao',3,'autorizado',falhas_gpt.pode_ler(),'usuario_id',auth.uid()) $$;

-- Revogar execução pública inclusive de helpers; liberar somente leitura e pontuação necessárias.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA falhas_gpt FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION falhas_gpt.pode_ler(),falhas_gpt.normalizar(text),falhas_gpt.tokens(text),
 falhas_gpt.canonizar(text),falhas_gpt.sim(text,text),falhas_gpt.distancia(text,text),falhas_gpt.proximidade_palavra(text,text),
 falhas_gpt.pontuar(text,text,text[],text,text,text[],text,text[]) TO authenticated;
REVOKE ALL ON FUNCTION public.buscar_fgpt_v3(text,integer,numeric),public.relacionados_fgpt_v3(uuid,integer),public.status_fgpt_v3() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.buscar_fgpt_v3(text,integer,numeric),public.relacionados_fgpt_v3(uuid,integer),public.status_fgpt_v3() TO authenticated;
-- Reprocessa índices ao reaplicar o instalador, sem alterar conteúdo operacional.
SELECT falhas_gpt.reindexar();
NOTIFY pgrst, 'reload schema';
COMMIT;
SELECT 'Motor V3 instalado. Autorize seu usuário em falhas_gpt.acessos e cadastre/importe o acervo.' AS resultado;
