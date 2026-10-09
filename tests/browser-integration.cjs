// Requires Playwright and a Chromium binary. Set FGPT_CHROMIUM to its local path.
const {chromium}=require('playwright');
const {spawn}=require('node:child_process');
const assert=require('node:assert/strict');
const {mkdirSync}=require('node:fs');
const titles=['Porta não fecha','Porta não abre','Isolamento de porta','Restabelecimento de portas','Portas: consulta de revisão','Portas: documentos relacionados'];
const rows=titles.map((topico,i)=>({id:`00000000-0000-4000-8000-00000000000${i+1}`,topico,categoria:'Portas',tipo:i===3?'restabelecimento':'procedimento',serie:'Teste de integração',resumo:'Resumo para teste da interface.',procedimento_completo:'Conteúdo de teste; sem instruções operacionais.',exemplo:true,aliases:[],relacionados:[],revisao:'TESTE',fonte:'Dados simulados de validação'}));
const scored=rows.map((r,i)=>({...r,relevancia:77.21-i*6,origem_match:i?'correspondência parcial':'palavras próximas ou erro de digitação',termo_encontrado:r.topico}));
(async()=>{
 mkdirSync('qa',{recursive:true});
 const server=spawn(process.execPath,['server.mjs'],{cwd:process.cwd()});let browser;
 try{
 await new Promise((resolve,reject)=>{server.stdout.once('data',resolve);server.once('error',reject);server.once('exit',c=>reject(new Error('Local server exited: '+c)));});
 browser=await chromium.launch({headless:true,executablePath:process.env.FGPT_CHROMIUM||'/tmp/fgpt-browser/chromium',args:['--no-sandbox','--disable-dev-shm-usage','--use-gl=angle','--use-angle=swiftshader','--disable-gpu'],env:{...process.env,LD_LIBRARY_PATH:'/tmp/fgpt-browser',FONTCONFIG_PATH:'/etc/fonts'}});
 for(const width of [1440,390]){
 const context=await browser.newContext({viewport:{width,height:900},reducedMotion:'reduce'});
 const page=await context.newPage();const errors=[];let authorized=true,denyData=false,refreshes=0,relatedCalls=0,loginCalls=0;
 page.on('pageerror',e=>errors.push(e.message));
 await page.route('https://fgpt-test.supabase.co/**',async route=>{
  const req=route.request(),url=new URL(req.url());const reply=(body,status=200)=>route.fulfill({status,contentType:'application/json',body:JSON.stringify(body)});
  if(url.pathname==='/auth/v1/token'){
   const data=req.postDataJSON();assert.equal(req.headers().apikey,'sb_publishable_test_only');
   if(url.searchParams.get('grant_type')==='password'){loginCalls++;assert.deepEqual(data,{email:'owner@example.invalid',password:'test-only-password'});}
   else{refreshes++;assert.equal(data.refresh_token,'mock-refresh');}
   return reply({access_token:'mock-access',refresh_token:'mock-refresh',expires_in:3600});
  }
  assert.equal(req.headers().authorization,'Bearer mock-access');
  if(url.pathname.endsWith('/status_fgpt_v3'))return reply({versao:3,autorizado:authorized});
  if(denyData)return reply({message:'permission denied'},403);
  if(url.pathname.endsWith('/vw_fgpt_acervo_v3'))return reply(rows);
  if(url.pathname.endsWith('/buscar_fgpt_v3')){const args=req.postDataJSON();assert.ok(args.p_busca);assert.equal(args.p_limite,10);return reply(scored);}
  if(url.pathname.endsWith('/relacionados_fgpt_v3')){relatedCalls++;return reply([{...scored[3],relevancia:100,origem_match:'relação cadastrada'}]);}
  throw new Error('Unexpected request: '+url.pathname);
 });
 await page.goto('http://127.0.0.1:4173/');
 const menu=async()=>{if(width<768)await page.getByRole('button',{name:'Abrir menu'}).click();};
 await menu();await page.getByRole('button',{name:'Conectar acervo Supabase'}).click();
 assert.equal(await page.locator('#sb-table').inputValue(),'vw_fgpt_acervo_v3');
 await page.locator('#sb-url').fill('https://fgpt-test.supabase.co');await page.locator('#sb-key').fill('sb_publishable_test_only');
 await page.getByRole('button',{name:'Testar e conectar'}).click();await page.getByText('Entre com seu usuário Supabase em Gerenciar conexão para consultar o acervo privado.',{exact:true}).waitFor();
 await page.locator('#sb-email').fill('owner@example.invalid');await page.locator('#sb-password').fill('test-only-password');
 authorized=false;await page.getByRole('button',{name:'Testar e conectar'}).click();await page.getByText('Seu usuário ainda não está autorizado. Use o SQL 03 para incluí-lo em falhas_gpt.acessos.',{exact:true}).waitFor();
 assert.equal(await page.evaluate(()=>localStorage.getItem('fgpt-supabase-v1')),null);
 authorized=true;await page.getByRole('button',{name:'Testar e conectar'}).click();await page.getByRole('dialog').waitFor({state:'hidden'});
 const stored=await page.evaluate(()=>({local:JSON.stringify(localStorage),session:JSON.stringify(sessionStorage)}));
 assert.ok(!stored.local.includes('password')&&!stored.local.includes('mock-access')&&!stored.local.includes('owner@'));assert.ok(!stored.session.includes('test-only-password'));
 if(width<768)assert.equal(await page.locator('.mobile-scrim.visible').count(),0);
 await page.locator('#chat-input').fill('porta nao fexa');await page.locator('#chat-input').press('Enter');
 await page.locator('.procedure-card h3').first().waitFor();assert.equal(await page.locator('.procedure-card h3').first().innerText(),'Porta não fecha');
 assert.match(await page.locator('.match-reason').first().innerText(),/palavras próximas/);assert.match(await page.locator('.relevance').first().innerText(),/77,2/);
 await page.getByRole('button',{name:'Ver todos os 6 resultados'}).click();assert.equal(await page.locator('.procedure-card').count(),6);
 assert.deepEqual(await page.locator('.procedure-card h3').allTextContents(),titles);
 await page.getByRole('button',{name:'Ver resumo',exact:true}).first().click();await page.waitForFunction(()=>document.querySelectorAll('.related-row').length===1);
 assert.match(await page.locator('.related-row').innerText(),/Restabelecimento/);assert.ok(relatedCalls>0);
 await page.getByRole('button',{name:'Ver procedimento completo',exact:true}).click();assert.match(await page.locator('#procedure-panel').innerText(),/Conteúdo de teste/);
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 await page.screenshot({path:`qa/v3-detail-${width}.png`});await page.keyboard.press('Escape');
 await page.evaluate(()=>{const k='fgpt-session:https://fgpt-test.supabase.co',v=JSON.parse(sessionStorage.getItem(k));v.expires_at=1;sessionStorage.setItem(k,JSON.stringify(v));});
 await page.reload();await page.waitForFunction(()=>document.querySelectorAll('.procedure-card').length===6);assert.equal(refreshes,1);
 await menu();await page.getByRole('button',{name:'Restabelecimentos',exact:true}).click();assert.equal(await page.locator('.procedure-card').count(),1);
 await menu();await page.getByRole('button',{name:'Nova consulta',exact:true}).click();
 await page.locator('#chat-input').fill('porta nao fexa');await page.locator('#chat-input').press('Enter');await page.locator('.procedure-card').first().waitFor();
 await page.evaluate(()=>window.scrollTo(0,0));await page.screenshot({path:`qa/v3-results-${width}.png`,fullPage:true});
 denyData=true;await page.reload();await page.getByRole('alert').waitFor();assert.match(await page.getByRole('alert').innerText(),/Acesso negado/);assert.equal(await page.locator('.procedure-card').count(),0);
 await menu();await page.getByRole('button',{name:'Gerenciar conexão'}).click();await page.getByRole('button',{name:'Desconectar',exact:true}).click();
 assert.equal(await page.evaluate(()=>localStorage.getItem('fgpt-supabase-v1')),null);assert.equal(await page.evaluate(()=>sessionStorage.getItem('fgpt-session:https://fgpt-test.supabase.co')),null);
 assert.ok(loginCalls>=2);assert.deepEqual(errors,[]);await context.close();
 console.log(`PASS V3 ${width}px: login, allowlist error, ranked results, all results, related RPC, full content, token refresh, permissions error, disconnect, no saved password or JS errors.`);
 }
 }finally{await browser?.close();server.kill();}
})().catch(e=>{console.error(e);process.exit(1)});
