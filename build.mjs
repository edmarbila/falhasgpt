import {rm,cp,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {PUBLIC_PROJECT} from './public/project-config.js';
import {validateConfig,V3_DEFAULTS} from './public/backend.js';
// Somente configuração pública. As variáveis são injetadas no artefato final.
const root=new URL('./',import.meta.url),output=new URL('./dist/',root);
const envURL=(process.env.FGPT_SUPABASE_URL||'').trim();
const envKey=(process.env.FGPT_SUPABASE_PUBLIC_KEY||'').trim();
let config=PUBLIC_PROJECT;
if(envURL||envKey){
 if(!envURL||!envKey)throw new Error('Preencha juntas FGPT_SUPABASE_URL e FGPT_SUPABASE_PUBLIC_KEY.');
 config={url:envURL,key:envKey};
}
if(config){
 if(/COLE_AQUI|SEU-PROJETO|COLE_SUA|YOUR_PROJECT/i.test(config.url+' '+config.key))throw new Error('Substitua os exemplos pela URL e chave pública reais.');
 config=validateConfig({...V3_DEFAULTS,...config});
}else if(process.argv.includes('--require-config')){
 throw new Error('Configure public/project-config.js ou as duas variáveis FGPT_SUPABASE_* antes do deploy.');
}
// Valida antes de apagar a compilação anterior.
await rm(output,{recursive:true,force:true});
await cp(new URL('./public/',root),output,{recursive:true});
await rm(new URL('project-config.example.js',output),{force:true});
await writeFile(new URL('project-config.js',output),'// Gerado pelo build. Somente configuração pública.\nexport const PUBLIC_PROJECT = '+JSON.stringify(config,null,2)+';\n');
await writeFile(new URL('.nojekyll',output),'');
await cp(new URL('./licenses/',root),new URL('./licenses/',output),{recursive:true});
console.log('Site estático gerado em '+fileURLToPath(output));
console.log(config?'Conexão central configurada.':'Sem conexão central: modo de configuração local. Use build:pages para exigir configuração.');
