import {PUBLIC_PROJECT} from './project-config.js';
import {accessToken,clearSession,signIn} from './auth.js';
import {demoProcedures,rankProcedures} from './data.js';
const KEY='fgpt-supabase-v1';
export const projectConfigured=!!PUBLIC_PROJECT;
export function readConfig(){try{return PUBLIC_PROJECT?{...V3_DEFAULTS,...PUBLIC_PROJECT}:JSON.parse(localStorage.getItem(KEY)||'null')}catch{return PUBLIC_PROJECT?{...V3_DEFAULTS,...PUBLIC_PROJECT}:null}}
export const V3_DEFAULTS={table:'vw_fgpt_acervo_v3',rpc:'buscar_fgpt_v3',queryParam:'p_busca',limitParam:'p_limite',orderColumn:'id'};
export function saveConfig(config){const safe=Object.fromEntries(['url','key','table','rpc','queryParam','limitParam','orderColumn'].map(k=>[k,config[k]||'']));localStorage.setItem(KEY,JSON.stringify(safe))}
export function clearConfig(){const c=readConfig();if(c)clearSession(c);localStorage.removeItem(KEY)}
export function validateConfig(config){
  let url;try{url=new URL(config.url)}catch{throw new Error('Informe uma URL válida do projeto Supabase.')}
  if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash)throw new Error('Use a URL HTTPS do projeto, sem senha ou parâmetros.');
  if(!config.key)throw new Error('Informe a chave pública anon ou publishable.');
  if(config.key.startsWith('sb_secret_'))throw new Error('Use somente a chave pública. Chaves secret e service_role não são aceitas.');
  if(config.key.split('.').length===3){try{const segment=config.key.split('.')[1].replace(/-/g,'+').replace(/_/g,'/');const claims=JSON.parse(atob(segment));if(claims.role!=='anon')throw new Error('role')}catch{throw new Error('A chave JWT deve ter o perfil anon. Nunca use service_role.')}}
  else if(!config.key.startsWith('sb_publishable_'))throw new Error('Use uma chave pública anon JWT ou sb_publishable_.');
  if(!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(config.table))throw new Error('Informe o nome da tabela ou view de procedimentos.');
  if(!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(config.rpc))throw new Error('Informe um nome válido para a função de busca.');
  for(const k of ['queryParam','limitParam','orderColumn'])if(config[k]&&!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(config[k]))throw new Error('Nome de parâmetro ou coluna inválido.');
  config.url=url.origin;return config;
}
export async function request(config,path,options={}){
  const token=await accessToken(config);
  if(config.rpc==='buscar_fgpt_v3'&&!token)throw new Error('Entre com seu usuário Supabase em Gerenciar conexão para consultar o acervo privado.');
  const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),12000);
  try{
    const res=await fetch(config.url+path,{...options,signal:controller.signal,headers:{apikey:config.key,...(token?{Authorization:'Bearer '+token}:config.key.startsWith('ey')?{Authorization:'Bearer '+config.key}:{}),'Content-Type':'application/json',...options.headers}});
    if(!res.ok){let body={};try{body=await res.json()}catch{}; if(res.status===401||res.status===403)throw new Error('Acesso negado pelo Supabase. Entre novamente e confira se seu usuário está autorizado no acervo.');if(body.code==='PGRST202'){const e=new Error('A função ainda não está disponível. Confira a instalação SQL V4/V5 no projeto conectado.');e.code=body.code;throw e;}if(['P0001','23514','40001'].includes(body.code))throw new Error(body.message);throw new Error('Supabase respondeu '+res.status+'. Confira a tabela, a função e suas permissões.');}
    return await res.json();
  }catch(e){if(e.name==='AbortError')throw new Error('O Supabase demorou para responder. Tente novamente.');if(e instanceof TypeError)throw new Error('Não foi possível conectar ao Supabase. Verifique a URL e a rede.');throw e}finally{clearTimeout(timer)}
}
const text=v=>typeof v==='string'?v:Array.isArray(v)?v.map(text).filter(Boolean).join('\n\n'):v&&typeof v==='object'?Object.entries(v).map(([k,val])=>k+': '+text(val)).join('\n'):v==null?'':String(v);
const first=(row,names)=>names.map(n=>row[n]).find(v=>v!=null&&v!=='');
export function mapProcedure(row,index=0){
  const type=String(first(row,['tipo','type'])||'procedimento').toLowerCase();
  const aliases=first(row,['aliases','sinonimos','palavras_chave'])||[];
  return {id:String(first(row,['id','procedimento_id','topico_id'])||'row-'+index),code:text(row.codigo),number:row.numero_sequencial,documentNumber:text(row.numero_documento),title:text(first(row,['topico','titulo','title','nome']))||'Procedimento sem título',category:text(first(row,['categoria','sistema','category']))||'Geral',type:type.includes('restabelec')?'restabelecimento':'procedimento',series:text(first(row,['serie','frota','series']))||'Acervo',summary:text(first(row,['resumo','procedimento_resumido','summary','descricao'])),content:text(first(row,['conteudo_completo','procedimento_completo','conteudo','texto','content','passos'])),revision:text(first(row,['revisao','versao','revision'])),source:text(first(row,['fonte','documento','source'])),keywords:Array.isArray(row.palavras_chave)?row.palavras_chave.map(text):[],aliases:Array.isArray(aliases)?aliases.map(text):String(aliases).split(/[,;|]/),related:Array.isArray(row.relacionados)?row.relacionados.map(String):[],score:Number(first(row,['relevancia','score']))||0,matchReason:text(row.origem_match),matchedTerm:text(row.termo_encontrado),demo:row.exemplo===true};
}
export async function fetchCatalog(config){
  let result=[];let offset=0;const size=500;
  while(true){const rows=await request(config,'/rest/v1/'+encodeURIComponent(config.table)+'?select=*&order='+encodeURIComponent(config.orderColumn||'id')+'.asc&limit='+size+'&offset='+offset);if(!Array.isArray(rows))throw new Error('A tabela não retornou uma lista de procedimentos.');result.push(...rows);if(rows.length<size)break;offset+=size;if(offset>=10000)throw new Error('O acervo ultrapassou 10 mil registros. Configure uma view específica para o Falhas GPT.');}
  return result.map(mapProcedure);
}
export async function discoverRpc(config){
  if(config.queryParam)return config;
  let schema;try{schema=await request(config,'/rest/v1/')}catch{throw new Error('Informe o nome do parâmetro de texto da função de busca nas configurações.');}
  const def=schema.paths?.['/rpc/'+config.rpc]?.post;
  const ref=def?.parameters?.find(p=>p.in==='body')?.schema;
  const props=ref?.properties||(ref?.$ref?schema.definitions?.[ref.$ref.split('/').pop()]?.properties:null);
  if(!props)throw new Error('Não foi possível descobrir a assinatura da função. Informe o parâmetro de texto.');
  const entries=Object.entries(props);const strings=entries.filter(([_,v])=>v.type==='string');
  if(strings.length!==1)throw new Error('A função tem mais de um parâmetro de texto. Informe o parâmetro de pesquisa.');
  config.queryParam=strings[0][0];config.limitParam=entries.find(([_,v])=>v.type==='integer')?.[0]||'';return config;
}
export async function searchBackend(config,query,catalog){
  const args={[config.queryParam]:query};if(config.limitParam)args[config.limitParam]=10;
  const raw=await request(config,'/rest/v1/rpc/'+encodeURIComponent(config.rpc),{method:'POST',body:JSON.stringify(args)});
  const rows=Array.isArray(raw)?raw:Array.isArray(raw?.dados)?raw.dados:null;
  if(!rows)throw new Error('Formato inesperado na resposta da função de busca.');
  return rows.map((row,i)=>{const p=mapProcedure(row,i);const original=catalog.find(x=>x.id===p.id)||catalog.find(x=>x.title.toLowerCase()===p.title.toLowerCase());return original?{...original,score:p.score,matchReason:p.matchReason,matchedTerm:p.matchedTerm}:p}).sort((a,b)=>b.score-a.score);
}
export async function testConfig(config){
 validateConfig(config);
 if(config.rpc==='buscar_fgpt_v3'){const status=await request(config,'/rest/v1/rpc/status_fgpt_v3',{method:'POST',body:'{}'});if(!status.autorizado)throw new Error('Seu acesso ainda não está liberado. Confira o RE com o administrador ou vincule o RE à sua conta.');}
 const catalog=await fetchCatalog(config);const discovered=await discoverRpc(config);await searchBackend(discovered,'porta',catalog);return {config:discovered,catalog};
}
export async function connectWithLogin(config,email,password){validateConfig(config);if(email||password)await signIn(config,email,password);return testConfig(config)}
export async function fetchRelated(config,id,catalog){
 const rows=await request(config,'/rest/v1/rpc/relacionados_fgpt_v3',{method:'POST',body:JSON.stringify({p_id:id,p_limite:5})});
 if(!Array.isArray(rows))throw new Error('Formato inesperado nos tópicos relacionados.');
 return rows.map((row,i)=>{const p=mapProcedure(row,i);return {...(catalog.find(x=>x.id===p.id)||p),score:p.score,matchReason:p.matchReason}});
}
export {demoProcedures,rankProcedures};

export const rpc=(c,name,args={})=>request(c,'/rest/v1/rpc/'+encodeURIComponent(name),{method:'POST',body:JSON.stringify(args)});
export async function sessionInfo(c){if(!await accessToken(c))return null;try{return await rpc(c,'fgpt_sessao_v4');}catch(e){if(e.code==='PGRST202'){const info=await rpc(c,'status_fgpt_v3');return {...info,admin:false,nome:'Operador',versao:3};}throw e;}}
export async function uploadPDF(c,id,file){
 const path=id+'/'+crypto.randomUUID()+'.pdf',bucket='falhas-gpt-procedimentos';const token=await accessToken(c);if(!token)throw new Error('Entre novamente.');
 const response=await fetch(c.url+'/storage/v1/object/'+bucket+'/'+path,{method:'POST',headers:{apikey:c.key,Authorization:'Bearer '+token,'Content-Type':'application/pdf','x-upsert':'false'},body:file,signal:AbortSignal.timeout(120000)});
 if(!response.ok)throw new Error('Não foi possível enviar o PDF. Confira a configuração do Storage privado e a permissão administrativa.');
 try{return await rpc(c,'fgpt_admin_anexar_pdf_v4',{p_id:id,p_caminho:path,p_nome:file.name.slice(0,250),p_tamanho:file.size});}catch(e){await request(c,'/storage/v1/object/'+bucket,{method:'DELETE',body:JSON.stringify({prefixes:[path]})}).catch(()=>{});throw e;}
}
export async function pdfURL(c,path){const data=await request(c,'/storage/v1/object/sign/falhas-gpt-procedimentos/'+path.split('/').map(encodeURIComponent).join('/'),{method:'POST',body:JSON.stringify({expiresIn:60})});const raw=data.signedURL||data.signedUrl;if(!raw)throw new Error('Não foi possível abrir o PDF.');const url=new URL(raw.startsWith('/object/')?'/storage/v1'+raw:raw,c.url);if(url.origin!==new URL(c.url).origin||!url.pathname.startsWith('/storage/v1/object/sign/'))throw new Error('Endereço de PDF inválido.');return url.href;}
