process.on('uncaughtException',e=>{console.error({message:e.message,code:e.code,where:e.where,position:e.position,stack:e.stack?.split('\n').slice(0,4).join('\n')});process.exit(1)});
import {PGlite} from '@electric-sql/pglite';
import {pg_trgm} from '@electric-sql/pglite/contrib/pg_trgm';
import {fuzzystrmatch} from '@electric-sql/pglite/contrib/fuzzystrmatch';
import fs from 'node:fs/promises';import assert from 'node:assert/strict';
let db=new PGlite({extensions:{pg_trgm,fuzzystrmatch}});
const admin='35eadffb-84a8-499c-8a24-bdb0231ef2de',operator='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222';
await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,raw_user_meta_data jsonb DEFAULT '{}',created_at timestamptz DEFAULT now());
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
GRANT USAGE ON SCHEMA auth TO authenticated,anon; GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated,anon;
CREATE SCHEMA storage;CREATE TABLE storage.buckets(id text PRIMARY KEY,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
CREATE TABLE storage.objects(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),bucket_id text,name text);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;GRANT USAGE ON SCHEMA storage TO authenticated,anon;GRANT SELECT,INSERT,DELETE,UPDATE ON storage.objects TO authenticated,anon;
CREATE POLICY generic_old_policy ON storage.objects FOR ALL TO authenticated,anon USING(true) WITH CHECK(true);
INSERT INTO auth.users(id,email) VALUES ('${admin}','admin@example.invalid'),('${other}','old@example.invalid');
CREATE FUNCTION public.buscar_fgpt_v2(text,integer) RETURNS text LANGUAGE sql AS $$ SELECT 'preservada'::text $$;`);

const v4=await fs.readFile('sql/v4/01_INSTALAR_ATUALIZACAO_V4.sql','utf8'),v5=await fs.readFile('sql/v5/04_ATUALIZAR_V4_PARA_V5.sql','utf8');
if(process.env.FGPT_TRGM_SCHEMA==='public')await db.exec('CREATE EXTENSION pg_trgm WITH SCHEMA public');
await db.exec(v4);await db.exec(await fs.readFile('sql/v4/02_PDFS_PRIVADOS.sql','utf8'));
// Represents existing content, indexed by V4 before this upgrade.
await db.query("INSERT INTO falhas_gpt.procedimentos(codigo,topico,tipo,categoria,serie,resumo,procedimento_completo,fonte,revisao,publicado) VALUES('antigo-01','Guia geral de bordo','procedimento','Pneumática','7000','Conferência do manômetro.',$1,'Documento fictício','1',true)",['Contexto neutro para teste. '.repeat(90)+'O pressostato auxiliar aparece somente neste trecho do documento.']);
// A fresh SQL Editor connection need not have loaded pg_trgm's custom GUCs.
// Use an ordinary object owner, never a superuser, to reproduce the reported 42501.
await db.exec(`CREATE ROLE fgpt_migrator NOSUPERUSER NOBYPASSRLS;
GRANT USAGE ON SCHEMA auth,extensions,storage TO fgpt_migrator;
GRANT SELECT ON storage.objects TO fgpt_migrator;
CREATE POLICY migration_owner_storage_read ON storage.objects FOR SELECT TO fgpt_migrator USING(true);
GRANT USAGE,CREATE ON SCHEMA public TO fgpt_migrator;
ALTER SCHEMA falhas_gpt OWNER TO fgpt_migrator;
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT c.oid::regclass AS obj FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='falhas_gpt' AND c.relkind='r' LOOP EXECUTE format('ALTER TABLE %s OWNER TO fgpt_migrator',r.obj); END LOOP;
 FOR r IN SELECT c.oid::regclass AS obj FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='falhas_gpt' AND c.relkind='S' LOOP EXECUTE format('ALTER SEQUENCE %s OWNER TO fgpt_migrator',r.obj); END LOOP;
 FOR r IN SELECT p.oid::regprocedure AS obj FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='falhas_gpt' OR (n.nspname='public' AND (p.proname LIKE 'fgpt_%' OR p.proname IN ('buscar_fgpt_v3','relacionados_fgpt_v3','status_fgpt_v3')))
 LOOP EXECUTE format('ALTER FUNCTION %s OWNER TO fgpt_migrator',r.obj); END LOOP;
END $$;
ALTER VIEW public.vw_fgpt_acervo_v3 OWNER TO fgpt_migrator;`);
const snapshot=await db.dumpDataDir();await db.close();
db=new PGlite({extensions:{pg_trgm,fuzzystrmatch},loadDataDir:snapshot});
await db.exec('SET ROLE fgpt_migrator');
assert.equal((await db.query('SELECT rolsuper FROM pg_roles WHERE rolname=current_user')).rows[0].rolsuper,false);
const withOldSettings=v5.replace(' LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog',
 ' LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog SET pg_trgm.similarity_threshold=0.15 SET pg_trgm.word_similarity_threshold=0.25');
await assert.rejects(db.exec(withOldSettings),e=>e.code==='42501'&&/pg_trgm.similarity_threshold/.test(e.message));
await db.exec('ROLLBACK');
assert.equal((await db.query("SELECT count(*)::int n FROM information_schema.columns WHERE table_schema='falhas_gpt' AND table_name='procedimentos' AND column_name='excluido_em'")).rows[0].n,0);
assert.equal((await db.query('SELECT count(*)::int n FROM falhas_gpt.migracoes WHERE versao=5')).rows[0].n,0);
assert.equal((await db.query('SELECT count(*)::int n FROM falhas_gpt.procedimentos')).rows[0].n,1);
await db.exec(v5);await db.exec(v5);
const validation=await db.exec(await fs.readFile('sql/v5/05_VALIDAR_V5.sql','utf8'));
assert.ok(Object.values(validation.at(-1).rows[0]).every(x=>x===true));
assert.equal((await db.query("SELECT current_setting('pg_trgm.similarity_threshold') s,current_setting('pg_trgm.word_similarity_threshold') w")).rows[0].s,'0.3');
const login=async id=>{await db.exec('RESET ROLE; SET ROLE authenticated;');await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[id]);};
const call=async(name,args=[])=>(await db.query(`SELECT public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) v`,args)).rows[0].v;
await login(admin);assert.equal((await call('fgpt_sessao_v4')).versao,5);
const original=(await db.query("SELECT * FROM public.buscar_fgpt_v3('pressostato auxiliar')")).rows[0];assert.equal(original.topico,'Guia geral de bordo');assert.match(original.origem_match,/conteúdo completo/);assert.match(original.termo_encontrado,/pressostato auxiliar/);assert.ok(Number(original.relevancia)<=78);
assert.ok((await db.query("SELECT * FROM public.buscar_fgpt_v3('presostato auxliar')")).rows.some(x=>x.id===original.id));
const typoBefore=(await db.query("SELECT id,relevancia,termo_encontrado FROM public.buscar_fgpt_v3('presostato auxliar')")).rows;
// The host's global/session thresholds must not change recall, scoring or snippets.
await db.exec('RESET ROLE; SET pg_trgm.similarity_threshold=0.99; SET pg_trgm.word_similarity_threshold=0.99');
await login(admin);
assert.deepEqual((await db.query("SELECT id,relevancia,termo_encontrado FROM public.buscar_fgpt_v3('presostato auxliar')")).rows,typoBefore);
assert.match((await db.query("SELECT * FROM public.buscar_fgpt_v3('manômetro')")).rows[0].origem_match,/resumo/);
const input={topico:'Pressostato auxiliar',tipo:'procedimento',categoria:'Pneumática',serie:'7000',resumo:'Resumo de QA',procedimento_completo:'Texto fictício de QA.',fonte:'Teste',revisao:'1',publicado:true};
const exact=await call('fgpt_admin_salvar_procedimento_v4',[input]);assert.equal((await db.query("SELECT * FROM public.buscar_fgpt_v3('pressostato auxiliar')")).rows[0].id,exact.id);
const topic=await call('fgpt_admin_criar_topico_v5',['Novo assunto do compressor','procedimento','Pneumática','7000']);assert.equal(topic.item.publicado,false);assert.equal(topic.existente,false);
assert.equal((await call('fgpt_admin_criar_topico_v5',['novo assunto do compressor','procedimento'])).existente,true);
assert.ok((await call('fgpt_admin_topicos_v5',['compressor'])).some(x=>x.id===topic.item.id));
const parent=await call('fgpt_admin_salvar_procedimento_v4',[{...input,relacionados:[original.id,topic.item.id]},exact.id,1]);
const pdfpath=original.id+'/66666666-6666-4666-8666-666666666666.pdf';await db.query('INSERT INTO storage.objects(bucket_id,name) VALUES($1,$2)',['falhas-gpt-procedimentos',pdfpath]);await call('fgpt_admin_anexar_pdf_v4',[original.id,pdfpath,'teste.pdf',100]);
await call('fgpt_admin_liberar_res_v4',[['59-00001']]);await login(other);await call('fgpt_vincular_re_v4',['59-00001','Operador QA']);assert.equal((await db.query('SELECT * FROM storage.objects')).rows.length,1);
for(const [name,args] of [['fgpt_admin_excluir_procedimento_v5',[original.id,1]],['fgpt_admin_topicos_v5',[]],['fgpt_admin_criar_topico_v5',['Ataque']]])await assert.rejects(call(name,args),/exclusivo/);
await login(admin);await assert.rejects(call('fgpt_admin_excluir_procedimento_v5',[original.id,99]),/Outro acesso/);await call('fgpt_admin_excluir_procedimento_v5',[original.id,1]);
assert.ok(!(await call('fgpt_admin_listar_procedimentos_v4')).items.some(x=>x.id===original.id));
assert.ok(!(await call('fgpt_admin_topicos_v5',['bordo'])).some(x=>x.id===original.id));
assert.ok(!(await call('fgpt_admin_obter_procedimento_v4',[parent.id])).relacionados.includes(original.id));
await assert.rejects(call('fgpt_admin_salvar_procedimento_v4',[input,original.id,2]),/não encontrado/);
await login(other);assert.equal((await db.query('SELECT * FROM storage.objects')).rows.length,0);assert.equal((await db.query('SELECT * FROM public.vw_fgpt_acervo_v3 WHERE id=$1',[original.id])).rows.length,0);assert.equal((await db.query("SELECT * FROM public.buscar_fgpt_v3('manômetro')")).rows.length,0);
await db.exec('RESET ROLE');assert.equal((await db.query('SELECT count(*)::int n FROM falhas_gpt.procedimentos WHERE id=$1 AND excluido_em IS NOT NULL',[original.id])).rows[0].n,1);await db.exec(v5);
await login(admin);const updated=await call('fgpt_admin_salvar_procedimento_v4',[{...input,procedimento_completo:'Encontramos neste texto o transdutor especial.'},exact.id,parent.versao_edicao+1]);assert.match((await db.query("SELECT * FROM public.buscar_fgpt_v3('transdutor especial')")).rows[0].origem_match,/conteúdo/);
await call('fgpt_admin_salvar_procedimento_v4',[input,exact.id,updated.versao_edicao]);assert.equal((await db.query("SELECT * FROM public.buscar_fgpt_v3('transdutor especial')")).rows.length,0);
await db.exec('RESET ROLE;SET ROLE anon');await assert.rejects(call('fgpt_admin_excluir_procedimento_v5',[exact.id,3]),/permission denied/);
await db.close();
const {rankProcedures}=await import('../public/data.js');const records=[{id:'a',title:'Guia geral',summary:'Instrumento manômetro',content:'Contexto. '.repeat(90)+'O pressostato auxiliar está aqui.',aliases:[]},{id:'b',title:'Pressostato auxiliar',summary:'',content:'',aliases:[]}];
assert.equal(rankProcedures(records,'pressostato auxiliar')[0].id,'b');assert.match(rankProcedures(records,'pressostato auxiliar').find(x=>x.id==='a').matchReason,/conteúdo/);assert.equal(rankProcedures(records,'presostato auxliar').find(x=>x.id==='a').id,'a');assert.match(rankProcedures(records,'manômetro')[0].matchReason,/resumo/);
console.log('PASS V5: reproduced 42501 in cold non-superuser session; failed migration rolled back; corrected migration/reapply as non-superuser; extension schema '+(process.env.FGPT_TRGM_SCHEMA||'extensions')+'; thresholds do not affect results. Full-text, typo, summary, title priority, snippets, drafts, authorization, deletion, audit and local ranking pass.');
