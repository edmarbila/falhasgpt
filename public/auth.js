// Only public project keys are persistent. Passwords are never saved.
const PREFIX='fgpt-session:';
const refreshes=new Map();
const key=c=>PREFIX+new URL(c.url).origin;
export function clearSession(c){try{sessionStorage.removeItem(key(c))}catch{}}
function read(c){try{return JSON.parse(sessionStorage.getItem(key(c))||'null')}catch{return null}}
export function saveSession(c,data){if(!data.access_token||!data.refresh_token)throw new Error('A autenticação não retornou uma sessão válida.');sessionStorage.setItem(key(c),JSON.stringify({access_token:data.access_token,refresh_token:data.refresh_token,expires_at:data.expires_at||Math.floor(Date.now()/1000)+(data.expires_in||3600)}));}
async function authRequest(c,grant,body){
 const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),12000);
 try{const res=await fetch(new URL('/auth/v1/token?grant_type='+grant,c.url).href,{method:'POST',headers:{apikey:c.key,'Content-Type':'application/json'},body:JSON.stringify(body),signal:controller.signal});
 if(!res.ok){if(grant==='refresh_token')clearSession(c);throw new Error(res.status===429?'Muitas tentativas de login. Aguarde e tente novamente.':'Não foi possível entrar. Confira seu e-mail, senha e a confirmação do cadastro no Supabase.');}
 const data=await res.json();saveSession(c,data);return data.access_token;
 }catch(e){if(e.name==='AbortError')throw new Error('O login demorou para responder. Tente novamente.');if(e instanceof TypeError)throw new Error('Não foi possível acessar o login do Supabase. Verifique a conexão.');throw e}finally{clearTimeout(timer)}
}
export async function signIn(c,email,password){if(!email||!password)throw new Error('Informe o e-mail e a senha do seu usuário no Supabase.');return authRequest(c,'password',{email:email.trim(),password})}
export async function accessToken(c){
 const session=read(c);if(!session)return null;
 if(session.expires_at>Date.now()/1000+60)return session.access_token;
 const k=key(c);if(!refreshes.has(k))refreshes.set(k,authRequest(c,'refresh_token',{refresh_token:session.refresh_token}).finally(()=>refreshes.delete(k)));
 return refreshes.get(k);
}

export async function signUp(c,{nome,re,email,password}){
 const endpoint=new URL('/auth/v1/signup',c.url);endpoint.searchParams.set('redirect_to',new URL('./',import.meta.url).href);
 const response=await fetch(endpoint,{method:'POST',headers:{apikey:c.key,'Content-Type':'application/json'},body:JSON.stringify({email:email.trim(),password,data:{app:'falhas_gpt',nome:nome.trim(),re}}),signal:AbortSignal.timeout(20000)});
 const data=await response.json();
 if(!response.ok)throw new Error(response.status===429?'Aguarde antes de tentar novamente.':'Cadastro não concluído. Confira se o RE foi liberado, se já está vinculado a outra conta e se a senha atende aos requisitos.');
 if(data.access_token&&data.refresh_token)saveSession(c,data);
 return {loggedIn:!!data.access_token};
}
export async function signOut(c){const token=await accessToken(c).catch(()=>null);clearSession(c);if(token)fetch(new URL('/auth/v1/logout?scope=local',c.url),{method:'POST',headers:{apikey:c.key,Authorization:'Bearer '+token},signal:AbortSignal.timeout(10000)}).catch(()=>{});}

export function consumeAuthRedirect(c){const p=new URLSearchParams(location.hash.slice(1));if(p.get('access_token')&&p.get('refresh_token')){saveSession(c,{access_token:p.get('access_token'),refresh_token:p.get('refresh_token'),expires_in:Number(p.get('expires_in'))||3600});history.replaceState(null,'',location.pathname+location.search);}}
