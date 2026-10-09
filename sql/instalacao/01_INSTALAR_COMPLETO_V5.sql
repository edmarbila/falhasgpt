-- FALHAS GPT — INSTALAÇÃO NOVA COMPLETA V5 (distribuição 5.1.0, 08/10/2026)
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
-- FALHAS GPT V4 — INSTALADOR COMPLETO E TRANSACIONAL
-- Cole inteiro no SQL Editor. Não precisa do antigo SQL 03.
-- Preserva funções V2, procedimentos e usuários existentes.

DO $$ BEGIN
 IF current_setting('server_version_num')::integer < 150000 THEN RAISE EXCEPTION 'Requer PostgreSQL 15 ou superior.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=(SELECT admin_id FROM pg_temp.fgpt_instalacao_config)) THEN RAISE EXCEPTION 'Administrador não encontrado neste projeto. Nenhuma alteração aplicada. Verifique o UUID em Authentication > Users.'; END IF;
END $$;
-- FALHAS GPT · MOTOR DE BUSCA V3 · PostgreSQL 15+ / Supabase
-- Execute inteiro no SQL Editor. Aditivo: não altera buscar_fgpt_v2 nem importa acervo antigo.
-- Privacidade: somente usuários autenticados e cadastrados em falhas_gpt.acessos leem o acervo.
-- Nenhum procedimento operacional é inventado por este script.

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
DO $view$ BEGIN IF to_regclass('public.vw_fgpt_acervo_v3') IS NULL THEN EXECUTE $definition$CREATE OR REPLACE VIEW public.vw_fgpt_acervo_v3 WITH (security_invoker=true) AS
 SELECT id,codigo,topico,categoria,tipo,serie,resumo,procedimento_completo,aliases,palavras_chave,
 relacionados,fonte,revisao,exemplo,atualizado_em FROM falhas_gpt.procedimentos WHERE publicado;$definition$; END IF; END $view$;
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

-- Migração V4: executar pelo instalador completo, depois do motor V3, na mesma transação.
-- Somente altera objetos Falhas GPT. Não apaga usuários, registros ou funções V2.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=(SELECT admin_id FROM pg_temp.fgpt_instalacao_config)) THEN
  RAISE EXCEPTION 'Administrador informado não existe neste projeto. Verifique Authentication > Users. Nenhuma alteração foi aplicada.';
 END IF;
END $$;

CREATE TABLE IF NOT EXISTS falhas_gpt.administradores(
 usuario_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 ativo boolean NOT NULL DEFAULT true, criado_em timestamptz NOT NULL DEFAULT now()
);
INSERT INTO falhas_gpt.administradores(usuario_id) VALUES((SELECT admin_id FROM pg_temp.fgpt_instalacao_config))
 ON CONFLICT(usuario_id) DO UPDATE SET ativo=true;
INSERT INTO falhas_gpt.acessos(usuario_id) VALUES((SELECT admin_id FROM pg_temp.fgpt_instalacao_config)) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS falhas_gpt.res_liberados(
 re text PRIMARY KEY CHECK(re ~ '^59-[0-9]{5}$'),
 ativo boolean NOT NULL DEFAULT true,
 usuario_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
 criado_em timestamptz NOT NULL DEFAULT now(), atualizado_em timestamptz NOT NULL DEFAULT now(),
 criado_por uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
CREATE TABLE IF NOT EXISTS falhas_gpt.perfis(
 usuario_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 re text UNIQUE NOT NULL REFERENCES falhas_gpt.res_liberados(re),
 nome text NOT NULL CHECK(length(trim(nome)) BETWEEN 2 AND 100),
 criado_em timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS falhas_gpt.auditoria(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 usuario_id uuid, acao text NOT NULL, objeto text, detalhes jsonb NOT NULL DEFAULT '{}',
 criado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE falhas_gpt.administradores ENABLE ROW LEVEL SECURITY;
ALTER TABLE falhas_gpt.res_liberados ENABLE ROW LEVEL SECURITY;
ALTER TABLE falhas_gpt.perfis ENABLE ROW LEVEL SECURITY;
ALTER TABLE falhas_gpt.auditoria ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON falhas_gpt.administradores,falhas_gpt.res_liberados,falhas_gpt.perfis,falhas_gpt.auditoria FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION falhas_gpt.e_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM falhas_gpt.administradores WHERE usuario_id=auth.uid() AND ativo)
$$;
CREATE OR REPLACE FUNCTION falhas_gpt.exigir_admin()
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN IF NOT falhas_gpt.e_admin() THEN RAISE EXCEPTION 'Acesso exclusivo do administrador.' USING ERRCODE='42501'; END IF; END $$;
CREATE OR REPLACE FUNCTION falhas_gpt.normalizar_re(p_re text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT CASE WHEN regexp_replace(trim(coalesce(p_re,'')),'[- ]','','g') ~ '^59[0-9]{5}$'
 THEN '59-'||right(regexp_replace(trim(p_re),'[- ]','','g'),5) ELSE NULL END
$$;
CREATE OR REPLACE FUNCTION falhas_gpt.pode_ler()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT falhas_gpt.e_admin() OR EXISTS(
  SELECT 1 FROM falhas_gpt.perfis p JOIN falhas_gpt.res_liberados r ON r.re=p.re
  WHERE p.usuario_id=auth.uid() AND r.usuario_id=p.usuario_id AND r.ativo
 )
$$;

-- Aplicado apenas a cadastros explicitamente destinados ao Falhas GPT.
-- Usuários de outros apps do mesmo Supabase continuam sem alteração e não ganham acesso ao Falhas GPT.
CREATE OR REPLACE FUNCTION falhas_gpt.validar_novo_usuario()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v_re text; v_nome text; v_liberado falhas_gpt.res_liberados%ROWTYPE;
BEGIN
 IF coalesce(NEW.raw_user_meta_data->>'app','')<>'falhas_gpt' THEN RETURN NEW; END IF;
 v_re:=falhas_gpt.normalizar_re(NEW.raw_user_meta_data->>'re');
 v_nome:=trim(coalesce(NEW.raw_user_meta_data->>'nome',''));
 IF v_re IS NULL OR length(v_nome) NOT BETWEEN 2 AND 100 THEN
  RAISE EXCEPTION 'Cadastro não autorizado: confira seu nome e RE.' USING ERRCODE='23514';
 END IF;
 SELECT * INTO v_liberado FROM falhas_gpt.res_liberados WHERE re=v_re FOR UPDATE;
 IF NOT FOUND OR NOT v_liberado.ativo OR v_liberado.usuario_id IS NOT NULL THEN
  RAISE EXCEPTION 'Cadastro não autorizado. Consulte o administrador.' USING ERRCODE='23514';
 END IF;
 INSERT INTO falhas_gpt.perfis(usuario_id,re,nome) VALUES(NEW.id,v_re,v_nome);
 UPDATE falhas_gpt.res_liberados SET usuario_id=NEW.id,atualizado_em=now() WHERE re=v_re;
 INSERT INTO falhas_gpt.auditoria(usuario_id,acao,objeto) VALUES(NEW.id,'cadastro',v_re);
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS fgpt_validar_cadastro_v4 ON auth.users;
CREATE TRIGGER fgpt_validar_cadastro_v4 AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION falhas_gpt.validar_novo_usuario();

CREATE OR REPLACE FUNCTION public.fgpt_sessao_v4()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('versao',4,'usuario_id',auth.uid(),'autorizado',falhas_gpt.pode_ler(),
 'admin',falhas_gpt.e_admin(),'nome',coalesce((SELECT nome FROM falhas_gpt.perfis WHERE usuario_id=auth.uid()),'Administrador'),
 're',(SELECT re FROM falhas_gpt.perfis WHERE usuario_id=auth.uid()))
$$;
CREATE OR REPLACE FUNCTION public.status_fgpt_v3()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$ SELECT public.fgpt_sessao_v4() $$;

-- Conta antiga já existente: o próprio usuário pode vincular UM RE liberado, uma única vez.
CREATE OR REPLACE FUNCTION public.fgpt_vincular_re_v4(p_re text,p_nome text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE r falhas_gpt.res_liberados%ROWTYPE; v_re text:=falhas_gpt.normalizar_re(p_re);
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre na sua conta.' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM falhas_gpt.perfis WHERE usuario_id=auth.uid()) THEN RAISE EXCEPTION 'Esta conta já possui RE vinculado.'; END IF;
 IF v_re IS NULL OR length(trim(coalesce(p_nome,''))) NOT BETWEEN 2 AND 100 THEN RAISE EXCEPTION 'Confira nome e RE.'; END IF;
 SELECT * INTO r FROM falhas_gpt.res_liberados WHERE re=v_re FOR UPDATE;
 IF NOT FOUND OR NOT r.ativo OR r.usuario_id IS NOT NULL THEN RAISE EXCEPTION 'RE indisponível. Consulte o administrador.'; END IF;
 INSERT INTO falhas_gpt.perfis(usuario_id,re,nome) VALUES(auth.uid(),v_re,trim(p_nome));
 UPDATE falhas_gpt.res_liberados SET usuario_id=auth.uid(),atualizado_em=now() WHERE re=v_re;
 INSERT INTO falhas_gpt.auditoria(usuario_id,acao,objeto) VALUES(auth.uid(),'vinculo_re',v_re);
 RETURN public.fgpt_sessao_v4();
END $$;
CREATE OR REPLACE FUNCTION public.fgpt_admin_liberar_res_v4(p_res text[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v text; n integer:=0; existentes integer:=0; bloqueados integer:=0;
BEGIN
 PERFORM falhas_gpt.exigir_admin();
 IF p_res IS NULL OR cardinality(p_res) NOT BETWEEN 1 AND 5000 THEN RAISE EXCEPTION 'Informe entre 1 e 5000 REs.'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_res) x WHERE falhas_gpt.normalizar_re(x) IS NULL) THEN RAISE EXCEPTION 'Há RE inválido. Use 59-00000.'; END IF;
 FOR v IN SELECT DISTINCT falhas_gpt.normalizar_re(x) FROM unnest(p_res) x ORDER BY 1 LOOP
  INSERT INTO falhas_gpt.res_liberados(re,criado_por) VALUES(v,auth.uid()) ON CONFLICT DO NOTHING;
  IF FOUND THEN n:=n+1;
  ELSIF EXISTS(SELECT 1 FROM falhas_gpt.res_liberados WHERE re=v AND NOT ativo) THEN bloqueados:=bloqueados+1;
  ELSE existentes:=existentes+1; END IF;
 END LOOP;
 INSERT INTO falhas_gpt.auditoria(usuario_id,acao,detalhes) VALUES(auth.uid(),'liberar_res',jsonb_build_object('novos',n,'existentes',existentes,'bloqueados_preservados',bloqueados));
 RETURN jsonb_build_object('novos',n,'existentes',existentes,'bloqueados_preservados',bloqueados);
END $$;
CREATE OR REPLACE FUNCTION public.fgpt_admin_alterar_re_v4(p_re text,p_ativo boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v_re text:=falhas_gpt.normalizar_re(p_re);
BEGIN
 PERFORM falhas_gpt.exigir_admin();
 IF p_ativo IS NULL THEN RAISE EXCEPTION 'Informe o estado do RE.'; END IF;
 UPDATE falhas_gpt.res_liberados SET ativo=p_ativo,atualizado_em=now() WHERE re=v_re;
 IF NOT FOUND THEN RAISE EXCEPTION 'RE não encontrado.'; END IF;
 INSERT INTO falhas_gpt.auditoria(usuario_id,acao,objeto) VALUES(auth.uid(),CASE WHEN p_ativo THEN 'reativar_re' ELSE 'revogar_re' END,v_re);
 RETURN jsonb_build_object('re',v_re,'ativo',p_ativo);
END $$;
CREATE OR REPLACE FUNCTION public.fgpt_admin_listar_res_v4(p_busca text DEFAULT '',p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v jsonb;
BEGIN
 PERFORM falhas_gpt.exigir_admin();
 SELECT jsonb_build_object('total',(SELECT count(*) FROM falhas_gpt.res_liberados WHERE re ILIKE '%'||left(coalesce(p_busca,''),100)||'%'),
 'items',coalesce((SELECT jsonb_agg(x) FROM (
 SELECT r.re,r.ativo,r.usuario_id,r.criado_em,p.nome,u.email FROM falhas_gpt.res_liberados r
 LEFT JOIN falhas_gpt.perfis p ON p.usuario_id=r.usuario_id LEFT JOIN auth.users u ON u.id=r.usuario_id
 WHERE r.re ILIKE '%'||left(coalesce(p_busca,''),100)||'%' ORDER BY r.re LIMIT 50 OFFSET greatest(0,coalesce(p_offset,0))) x),'[]'::jsonb)) INTO v;
 RETURN v;
END $$;

ALTER TABLE falhas_gpt.procedimentos ADD COLUMN IF NOT EXISTS numero_sequencial bigint;
ALTER TABLE falhas_gpt.procedimentos ADD COLUMN IF NOT EXISTS numero_documento text NOT NULL DEFAULT '';
ALTER TABLE falhas_gpt.procedimentos ADD COLUMN IF NOT EXISTS versao_edicao integer NOT NULL DEFAULT 1;
CREATE UNIQUE INDEX IF NOT EXISTS fgpt_numero_sequencial_v4 ON falhas_gpt.procedimentos(numero_sequencial) WHERE numero_sequencial IS NOT NULL;
CREATE SEQUENCE IF NOT EXISTS falhas_gpt.procedimento_numero_v4;
-- Apenas eleva a sequência para evitar colisões; nunca reutiliza números existentes.
SELECT setval('falhas_gpt.procedimento_numero_v4',greatest(
 (SELECT last_value FROM falhas_gpt.procedimento_numero_v4),
 coalesce((SELECT max(numero_sequencial) FROM falhas_gpt.procedimentos),0),
 coalesce((SELECT max(substring(codigo from 'trafego-trens-falhasgptapp-([0-9]+)$')::bigint)
 FROM falhas_gpt.procedimentos WHERE codigo ~ '^trafego-trens-falhasgptapp-[0-9]{1,15}$'),0),1),
 (SELECT is_called FROM falhas_gpt.procedimento_numero_v4) OR EXISTS(SELECT 1 FROM falhas_gpt.procedimentos WHERE numero_sequencial IS NOT NULL OR codigo ~ '^trafego-trens-falhasgptapp-[0-9]{1,15}$'));
CREATE TABLE IF NOT EXISTS falhas_gpt.anexos(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),procedimento_id uuid NOT NULL REFERENCES falhas_gpt.procedimentos(id),
 caminho text UNIQUE NOT NULL,nome text NOT NULL,tamanho bigint NOT NULL CHECK(tamanho>0 AND tamanho<=20971520),
 criado_em timestamptz NOT NULL DEFAULT now(),criado_por uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE falhas_gpt.anexos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON falhas_gpt.anexos FROM PUBLIC,anon,authenticated;
GRANT SELECT ON falhas_gpt.anexos TO authenticated;
DROP POLICY IF EXISTS fgpt_anexos_leitura_v4 ON falhas_gpt.anexos;
CREATE POLICY fgpt_anexos_leitura_v4 ON falhas_gpt.anexos FOR SELECT TO authenticated
 USING(falhas_gpt.pode_ler() AND EXISTS(SELECT 1 FROM falhas_gpt.procedimentos p WHERE p.id=procedimento_id));

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
 IF EXISTS(SELECT 1 FROM unnest(v_rel) x WHERE NOT EXISTS(SELECT 1 FROM falhas_gpt.procedimentos WHERE id=x) OR x=p_id) THEN RAISE EXCEPTION 'Há relação inválida ou com o próprio procedimento.'; END IF;
 IF p_id IS NULL THEN
  n:=nextval('falhas_gpt.procedimento_numero_v4');
  INSERT INTO falhas_gpt.procedimentos(codigo,numero_sequencial,topico)
  VALUES('trafego-trens-falhasgptapp-'||lpad(n::text,greatest(2,length(n::text)),'0'),n,trim(p_dados->>'topico')) RETURNING * INTO v;
 ELSE
  SELECT * INTO v FROM falhas_gpt.procedimentos WHERE id=p_id FOR UPDATE;
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
 SELECT jsonb_build_object('total',(SELECT count(*) FROM falhas_gpt.procedimentos WHERE topico ILIKE '%'||left(coalesce(p_busca,''),200)||'%' OR codigo ILIKE '%'||left(coalesce(p_busca,''),200)||'%'),
 'items',coalesce((SELECT jsonb_agg(x) FROM(SELECT id,codigo,numero_sequencial,numero_documento,topico,categoria,tipo,serie,revisao,publicado,exemplo,versao_edicao,atualizado_em
 FROM falhas_gpt.procedimentos WHERE topico ILIKE '%'||left(coalesce(p_busca,''),200)||'%' OR codigo ILIKE '%'||left(coalesce(p_busca,''),200)||'%'
 ORDER BY atualizado_em DESC,id LIMIT 50 OFFSET greatest(0,coalesce(p_offset,0))) x),'[]'::jsonb)) INTO v;
 RETURN v;
END $$;
CREATE OR REPLACE FUNCTION public.fgpt_admin_obter_procedimento_v4(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v jsonb; BEGIN
 PERFORM falhas_gpt.exigir_admin();
 SELECT to_jsonb(p)||jsonb_build_object('anexos',coalesce((SELECT jsonb_agg(a) FROM falhas_gpt.anexos a WHERE a.procedimento_id=p.id),'[]'::jsonb)) INTO v FROM falhas_gpt.procedimentos p WHERE id=p_id;
 IF v IS NULL THEN RAISE EXCEPTION 'Procedimento não encontrado.'; END IF;
 RETURN v;
END $$;
CREATE OR REPLACE FUNCTION public.fgpt_anexos_v4(p_id uuid)
RETURNS SETOF falhas_gpt.anexos LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT * FROM falhas_gpt.anexos WHERE procedimento_id=p_id ORDER BY criado_em,id
$$;

-- Mantém operadores restritos a publicados; administrador vê também rascunhos.
DROP POLICY IF EXISTS fgpt_ler_procedimentos_v3 ON falhas_gpt.procedimentos;
CREATE POLICY fgpt_ler_procedimentos_v3 ON falhas_gpt.procedimentos FOR SELECT TO authenticated
 USING((publicado AND (SELECT falhas_gpt.pode_ler())) OR (SELECT falhas_gpt.e_admin()));
CREATE OR REPLACE VIEW public.vw_fgpt_acervo_v3 WITH(security_invoker=true) AS
 SELECT id,codigo,topico,categoria,tipo,serie,resumo,procedimento_completo,aliases,palavras_chave,relacionados,fonte,revisao,exemplo,atualizado_em,numero_sequencial,numero_documento
 FROM falhas_gpt.procedimentos WHERE publicado;

REVOKE ALL ON FUNCTION falhas_gpt.e_admin(),falhas_gpt.exigir_admin(),falhas_gpt.normalizar_re(text),falhas_gpt.validar_novo_usuario(),falhas_gpt.pode_ler() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION falhas_gpt.e_admin(),falhas_gpt.pode_ler() TO authenticated;
-- Checker booleano usado pelas barreiras do Storage; para anon retorna false.
GRANT EXECUTE ON FUNCTION falhas_gpt.e_admin() TO anon;
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT oid::regprocedure AS assinatura FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN(
 'fgpt_sessao_v4','fgpt_vincular_re_v4','fgpt_admin_liberar_res_v4','fgpt_admin_alterar_re_v4','fgpt_admin_listar_res_v4',
 'fgpt_admin_salvar_procedimento_v4','fgpt_admin_listar_procedimentos_v4','fgpt_admin_obter_procedimento_v4','fgpt_anexos_v4') LOOP
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.assinatura);
 EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.assinatura);
 END LOOP;
END $$;
CREATE TABLE IF NOT EXISTS falhas_gpt.migracoes(versao integer PRIMARY KEY,aplicado_em timestamptz NOT NULL DEFAULT now());
ALTER TABLE falhas_gpt.migracoes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON falhas_gpt.migracoes FROM PUBLIC,anon,authenticated;
INSERT INTO falhas_gpt.migracoes(versao) VALUES(4) ON CONFLICT DO NOTHING;

DO $$ BEGIN IF to_regprocedure('falhas_gpt.pode_ler_pdf(text)') IS NOT NULL THEN GRANT EXECUTE ON FUNCTION falhas_gpt.pode_ler_pdf(text) TO authenticated,anon; END IF; END $$;

SELECT falhas_gpt.reindexar();


-- Execute após 01_INSTALAR_ATUALIZACAO_V4.sql no SQL Editor do mesmo projeto.

DO $$ BEGIN
 IF to_regclass('storage.buckets') IS NULL OR to_regclass('falhas_gpt.anexos') IS NULL THEN
  RAISE EXCEPTION 'Instale a V4 e confirme que o Storage está disponível neste projeto.';
 END IF;
END $$;
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('falhas-gpt-procedimentos','falhas-gpt-procedimentos',false,20971520,ARRAY['application/pdf'])
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=20971520,allowed_mime_types=ARRAY['application/pdf'];
CREATE OR REPLACE FUNCTION falhas_gpt.pode_ler_pdf(p_caminho text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT falhas_gpt.e_admin() OR (falhas_gpt.pode_ler() AND EXISTS(
 SELECT 1 FROM falhas_gpt.anexos a JOIN falhas_gpt.procedimentos p ON p.id=a.procedimento_id WHERE a.caminho=p_caminho AND p.publicado))
$$;
REVOKE ALL ON FUNCTION falhas_gpt.pode_ler_pdf(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION falhas_gpt.pode_ler_pdf(text) TO authenticated,anon;
DROP POLICY IF EXISTS fgpt_pdf_ler_v4 ON storage.objects;
CREATE POLICY fgpt_pdf_ler_v4 ON storage.objects FOR SELECT TO authenticated
 USING(bucket_id='falhas-gpt-procedimentos' AND falhas_gpt.pode_ler_pdf(name));
DROP POLICY IF EXISTS fgpt_pdf_criar_v4 ON storage.objects;
CREATE POLICY fgpt_pdf_criar_v4 ON storage.objects FOR INSERT TO authenticated
 WITH CHECK(bucket_id='falhas-gpt-procedimentos' AND falhas_gpt.e_admin());
DROP POLICY IF EXISTS fgpt_pdf_excluir_v4 ON storage.objects;
CREATE POLICY fgpt_pdf_excluir_v4 ON storage.objects FOR DELETE TO authenticated
 USING(bucket_id='falhas-gpt-procedimentos' AND falhas_gpt.e_admin());
-- Barreiras restritivas impedem que políticas genéricas já existentes liberem este bucket.
-- Não restringem os buckets dos outros aplicativos.
DROP POLICY IF EXISTS fgpt_pdf_barreira_select_v4 ON storage.objects;
CREATE POLICY fgpt_pdf_barreira_select_v4 ON storage.objects AS RESTRICTIVE FOR SELECT TO PUBLIC
 USING(bucket_id IS DISTINCT FROM 'falhas-gpt-procedimentos' OR CASE WHEN auth.uid() IS NULL THEN false ELSE falhas_gpt.pode_ler_pdf(name) END);
DROP POLICY IF EXISTS fgpt_pdf_barreira_insert_v4 ON storage.objects;
CREATE POLICY fgpt_pdf_barreira_insert_v4 ON storage.objects AS RESTRICTIVE FOR INSERT TO PUBLIC
 WITH CHECK(bucket_id IS DISTINCT FROM 'falhas-gpt-procedimentos' OR CASE WHEN auth.uid() IS NULL THEN false ELSE falhas_gpt.e_admin() END);
DROP POLICY IF EXISTS fgpt_pdf_barreira_delete_v4 ON storage.objects;
CREATE POLICY fgpt_pdf_barreira_delete_v4 ON storage.objects AS RESTRICTIVE FOR DELETE TO PUBLIC
 USING(bucket_id IS DISTINCT FROM 'falhas-gpt-procedimentos' OR CASE WHEN auth.uid() IS NULL THEN false ELSE falhas_gpt.e_admin() END);
DROP POLICY IF EXISTS fgpt_pdf_barreira_update_v4 ON storage.objects;
CREATE POLICY fgpt_pdf_barreira_update_v4 ON storage.objects AS RESTRICTIVE FOR UPDATE TO PUBLIC
 USING(bucket_id IS DISTINCT FROM 'falhas-gpt-procedimentos' OR CASE WHEN auth.uid() IS NULL THEN false ELSE falhas_gpt.e_admin() END)
 WITH CHECK(bucket_id IS DISTINCT FROM 'falhas-gpt-procedimentos' OR CASE WHEN auth.uid() IS NULL THEN false ELSE falhas_gpt.e_admin() END);
CREATE OR REPLACE FUNCTION public.fgpt_admin_anexar_pdf_v4(p_id uuid,p_caminho text,p_nome text,p_tamanho bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v falhas_gpt.anexos%ROWTYPE;
BEGIN
 PERFORM falhas_gpt.exigir_admin();
 IF NOT EXISTS(SELECT 1 FROM falhas_gpt.procedimentos WHERE id=p_id) THEN RAISE EXCEPTION 'Procedimento não encontrado.'; END IF;
 IF p_caminho IS NULL OR split_part(p_caminho,'/',1)<>p_id::text OR p_caminho !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.pdf$' THEN RAISE EXCEPTION 'Caminho de PDF inválido.'; END IF;
 IF p_tamanho IS NULL OR p_tamanho NOT BETWEEN 1 AND 20971520 OR length(trim(coalesce(p_nome,''))) NOT BETWEEN 1 AND 250 THEN RAISE EXCEPTION 'Confira nome e tamanho do PDF (máximo 20 MB).'; END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='falhas-gpt-procedimentos' AND name=p_caminho) THEN RAISE EXCEPTION 'Envie o PDF antes de vinculá-lo.'; END IF;
 INSERT INTO falhas_gpt.anexos(procedimento_id,caminho,nome,tamanho,criado_por)
 VALUES(p_id,p_caminho,trim(p_nome),p_tamanho,auth.uid()) RETURNING * INTO v;
 INSERT INTO falhas_gpt.auditoria(usuario_id,acao,objeto) VALUES(auth.uid(),'anexar_pdf',v.id::text);
 RETURN to_jsonb(v);
END $$;
REVOKE ALL ON FUNCTION public.fgpt_admin_anexar_pdf_v4(uuid,text,text,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fgpt_admin_anexar_pdf_v4(uuid,text,text,bigint) TO authenticated;


-- FALHAS GPT V5 — aplicar INTEIRO depois da V4. Preserva usuários, REs e documentos.
-- Reaplicável. Não executar novamente os instaladores V3/V4 depois desta atualização.
-- Correção 2026-10-08: limites explícitos de similaridade, sem SET de parâmetros pg_trgm.
-- Preserva a pontuação e a ordem dos resultados. Não requer GRANT SET ou superusuário.

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
SELECT 'Instalação completa V5 concluída. Execute 02_VALIDAR_INSTALACAO_COMPLETA.sql.' AS resultado;
