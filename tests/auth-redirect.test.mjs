import assert from 'node:assert/strict';
import {accessToken,consumeAuthRedirect} from '../public/auth.js';

const data=new Map();
globalThis.sessionStorage={
 getItem(key){return data.get(key)??null;},
 setItem(key,value){data.set(key,String(value));},
 removeItem(key){data.delete(key);}
};
const calls=[];
globalThis.history={replaceState(...args){calls.push(args);}};
const config={url:'https://fgpt-test.supabase.co',key:'sb_publishable_test'};
const run=(hash,search='')=>{
 globalThis.location={hash,pathname:'/falhasgpt/',search};
 return consumeAuthRedirect(config);
};

// Sem callback: o hash de navegação comum não deve ser alterado.
assert.equal(run('#chat'),null);
assert.equal(calls.length,0);

// Confirmação de cadastro: o Supabase devolve tokens, mas a tela deve pedir login.
const confirmed=run('#access_token=verified-access&refresh_token=verified-refresh&expires_in=3600&type=signup');
assert.equal(confirmed.status,'confirmed');
assert.equal(await accessToken(config),null,'Confirmação não deve fazer login automático');
assert.deepEqual(calls.at(-1),[null,'','/falhasgpt/']);
assert.equal(run(''),null,'Recarregar após a confirmação não deve duplicar o aviso');

// Retorno incompleto ou erro não são provas de confirmação.
assert.equal(run('#access_token=partial&type=signup').status,'error');
assert.match(run('#error=access_denied&error_code=otp_expired&error_description=expired').message,/expirou/);
assert.deepEqual(calls.at(-1),[null,'','/falhasgpt/']);

// Outros retornos de autenticação mantêm o comportamento anterior de login.
const signed=run('#access_token=login-access&refresh_token=login-refresh&expires_in=3600&type=magiclink','?lang=pt');
assert.equal(signed.status,'signed_in');
assert.equal(await accessToken(config),'login-access');
assert.deepEqual(calls.at(-1),[null,'','/falhasgpt/?lang=pt']);

// Uma confirmação posterior deve solicitar login mesmo que haja sessão antiga.
assert.equal(run('#access_token=another-access&refresh_token=another-refresh&type=email').status,'confirmed');
assert.equal(await accessToken(config),null);
console.log('PASS auth redirect: confirmação pede login, links inválidos não mostram sucesso, tokens removidos da URL e sessão protegida.');
