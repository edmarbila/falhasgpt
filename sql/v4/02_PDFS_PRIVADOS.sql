-- Execute após 01_INSTALAR_ATUALIZACAO_V4.sql no SQL Editor do mesmo projeto.
BEGIN;
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
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'PDFs privados configurados. Somente o administrador envia; operadores autorizados leem anexos de procedimentos disponíveis.' resultado;
