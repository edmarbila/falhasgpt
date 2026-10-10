import fs from 'node:fs/promises';import {spawnSync} from 'node:child_process';import assert from 'node:assert/strict';
const env={...process.env};delete env.FGPT_SUPABASE_URL;delete env.FGPT_SUPABASE_PUBLIC_KEY;
const run=extra=>spawnSync(process.execPath,['build.mjs','--require-config'],{env:{...env,...extra},encoding:'utf8'});
// Nao exige que o arquivo local (ignorado no Git) exista num clone novo.
let original=null;
try{original=await fs.readFile('public/project-config.js','utf8');}
catch(e){if(e.code!=='ENOENT')throw e;}
// Mantem a configuracao do desenvolvedor intacta durante o teste.
try{
 await fs.writeFile('public/project-config.js','export const PUBLIC_PROJECT=null;\n');
 assert.notEqual(run({}).status,0);
 assert.notEqual(run({FGPT_SUPABASE_URL:'https://test.supabase.co'}).status,0);
 assert.notEqual(run({FGPT_SUPABASE_URL:'https://test.supabase.co',FGPT_SUPABASE_PUBLIC_KEY:'sb_secret_test'}).status,0);
 const jwt='e30.'+Buffer.from(JSON.stringify({role:'service_role'})).toString('base64url')+'.x';
 assert.notEqual(run({FGPT_SUPABASE_URL:'https://test.supabase.co',FGPT_SUPABASE_PUBLIC_KEY:jwt}).status,0);
 const good=run({FGPT_SUPABASE_URL:'https://fgpt-test.supabase.co',FGPT_SUPABASE_PUBLIC_KEY:'sb_publishable_test'});assert.equal(good.status,0,good.stderr);
 const built=await fs.readFile('dist/project-config.js','utf8');assert.match(built,/fgpt-test.supabase.co/);
 assert.equal((await fs.readdir('dist')).includes('sql'),false);assert.equal((await fs.readdir('dist')).includes('project-config.example.js'),false);
 await fs.access('dist/.nojekyll');await fs.access('dist/licenses/pdfjs-LICENSE');await fs.access('dist/vendor/pdfjs/pdf.worker.mjs');
 // A mesma pasta pronta precisa resolver assets sob / e sob /falhas-gpt/.
 for(const base of ['https://example.test/','https://example.test/falhas-gpt/']){
  const html=await fs.readFile('dist/index.html','utf8');
  for(const match of html.matchAll(/(?:src|href)="(\.\/[^"#]+)"/g)){
   const url=new URL(match[1],base);assert.ok(url.href.startsWith(base));await fs.access('dist/'+url.href.slice(base.length));
  }
  for(const name of ['style.css','v4.css']){
   const css=await fs.readFile('dist/'+name,'utf8');
   for(const match of css.matchAll(/url\(['"]?(\.\/[^'"\)]+)['"]?\)/g))await fs.access('dist/'+new URL(match[1],base+name).href.slice(base.length));
  }
 }
}finally{if(original===null)await fs.rm('public/project-config.js',{force:true});else await fs.writeFile('public/project-config.js',original);await fs.rm('dist',{recursive:true,force:true});}
console.log('PASS build Pages: configuração exigida, chaves privadas rejeitadas, assets locais, raiz/subpasta e artefato só com arquivos do site.');
