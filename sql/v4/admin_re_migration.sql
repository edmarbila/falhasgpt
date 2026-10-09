-- Migração V4: executar pelo instalador completo, depois do motor V3, na mesma transação.
-- Somente altera objetos Falhas GPT. Não apaga usuários, registros ou funções V2.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id='35eadffb-84a8-499c-8a24-bdb0231ef2de') THEN
  RAISE EXCEPTION 'Administrador 35eadffb-84a8-499c-8a24-bdb0231ef2de não existe neste projeto. Verifique Authentication > Users. Nenhuma alteração foi aplicada.';
 END IF;
END $$;

CREATE TABLE IF NOT EXISTS falhas_gpt.administradores(
 usuario_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 ativo boolean NOT NULL DEFAULT true, criado_em timestamptz NOT NULL DEFAULT now()
);
INSERT INTO falhas_gpt.administradores(usuario_id) VALUES('35eadffb-84a8-499c-8a24-bdb0231ef2de')
 ON CONFLICT(usuario_id) DO UPDATE SET ativo=true;
INSERT INTO falhas_gpt.acessos(usuario_id) VALUES('35eadffb-84a8-499c-8a24-bdb0231ef2de') ON CONFLICT DO NOTHING;
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
