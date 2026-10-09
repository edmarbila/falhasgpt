// Navigation fixtures only: no operational instructions are invented.
export const demoProcedures = [
  {id:'demo-001',title:'Porta não abre',category:'Portas',type:'procedimento',series:'Exemplo',aliases:['porta não abre','falha abertura de porta','porta travada','não consigo abrir a porta'],summary:'Exemplo de consulta para uma porta que não responde ao comando de abertura. O resumo operacional oficial ainda precisa ser conectado.',content:'Conteúdo de demonstração\n\nEste registro permite testar a pesquisa, a relevância e a passagem do resumo para o documento completo.\n\nO procedimento operacional de “Porta não abre” não foi disponibilizado nesta versão. A sequência de ações, as condições de aplicação e a revisão deverão vir do acervo oficial.\n\nNenhuma ação operacional está prescrita neste exemplo.',related:['demo-002','demo-003','demo-004'],demo:true},
  {id:'demo-002',title:'Porta não fecha',category:'Portas',type:'procedimento',series:'Exemplo',aliases:['porta não fecha','falha fechamento de porta','porta aberta','fechamento das portas'],summary:'Exemplo de consulta para uma porta que não responde ao comando de fechamento. Aguarda o resumo do acervo oficial.',content:'Conteúdo de demonstração\n\nEsta página demonstra a leitura do procedimento completo de “Porta não fecha”.\n\nO documento oficial, sua revisão e as condições de aplicação ainda não foram conectados. Este exemplo não contém instruções para operação do trem.',related:['demo-001','demo-003','demo-004'],demo:true},
  {id:'demo-003',title:'Isolamento de porta',category:'Portas',type:'procedimento',series:'Exemplo',aliases:['isolar porta','realizar isolamento','realizar o isolamento','isolamento da porta'],summary:'Exemplo de tópico de isolamento, com acesso a assuntos relacionados. As condições e instruções oficiais ainda precisam ser cadastradas.',content:'Conteúdo de demonstração\n\nEste é um exemplo de organização do tópico “Isolamento de porta”.\n\nA aplicação, as restrições e a sequência oficial não foram fornecidas. Conecte o acervo aprovado para disponibilizar esse conteúdo.',related:['demo-001','demo-002','demo-004'],demo:true},
  {id:'demo-004',title:'Restabelecimento de portas',category:'Portas',type:'restabelecimento',series:'Exemplo',aliases:['restabelecer portas','normalizar porta','restabelecimento de porta','retorno da porta'],summary:'Exemplo de navegação para restabelecimentos do sistema de portas. Aguarda conteúdo oficial e condições de aplicação.',content:'Conteúdo de demonstração\n\nEste registro demonstra a seção de restabelecimentos e sua ligação com procedimentos relacionados.\n\nNenhuma sequência de restabelecimento foi fornecida. O documento aprovado deverá ser conectado antes do uso operacional.',related:['demo-003','demo-001','demo-002'],demo:true},
];
export const normalize = text => String(text??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9 ]/g,' ').replace(/\s+/g,' ').trim();
const stop=new Set(['a','o','as','os','de','do','da','das','dos','e','um','uma','para','por','com','em','no','na','nos','nas','ao','aos','eu','me','meu','minha','que','como','qual','favor','preciso','quero','pode','poderia','realizar','fazer','procedimento','procedimentos','esta','estao','estou','trem','trens','sistema']);
const tokens=s=>[...new Set(normalize(s).split(' ').filter(x=>x&&!stop.has(x)))].sort();
const synonyms=[['nao consegue abrir','nao abre'],['nao consegue fechar','nao fecha'],['nao esta abrindo','nao abre'],['nao esta fechando','nao fecha'],['falha de abertura','nao abre'],['falha de fechamento','nao fecha'],['restabelecimentos','restabelecimento'],['restabelecer','restabelecimento'],['fechamento','fecha'],['fechando','fecha'],['abertura','abre'],['abrindo','abre'],['isolada','isolamento'],['isolado','isolamento'],['isolar','isolamento'],['portas','porta'],['fechar','fecha'],['abrir','abre']];
const canonical=s=>synonyms.reduce((v,[from,to])=>v.replace(new RegExp('\\b'+from+'\\b','g'),to),normalize(s));
function trigrams(s){const out=new Set();for(const w of normalize(s).split(' ').filter(Boolean)){const p='  '+w+' ';for(let i=0;i<p.length-2;i++)out.add(p.slice(i,i+3))}return out}
function similarity(a,b){const x=trigrams(a),y=trigrams(b);const common=[...x].filter(k=>y.has(k)).length;return common/(x.size+y.size-common||1)}
function distance(a,b){if(Math.abs(a.length-b.length)>2)return 3;let row=Array.from({length:b.length+1},(_,i)=>i);for(let i=1;i<=a.length;i++){const next=[i];for(let j=1;j<=b.length;j++)next[j]=Math.min(next[j-1]+1,row[j]+1,row[j-1]+(a[i-1]===b[j-1]?0:1));row=next}return row[b.length]}
function wordScore(a,b){if(a===b)return 1;if(Math.min(a.length,b.length)<4)return 0;const sim=similarity(a,b);const d=Math.max(a.length,b.length)<=60?distance(a,b):3;return Math.max(sim>=.4?sim:0,d<=2?Math.max(.5,1-d/Math.max(a.length,b.length)):0)}
const searchIndex=new WeakMap();
function phraseIndex(p){
 if(searchIndex.has(p))return searchIndex.get(p);
 const phrases=[['titulo',p.title],...(p.aliases||[]).map(x=>['alias',x]),...(p.keywords||[]).map(x=>['palavra_chave',x]),['contexto',[p.title,p.category,p.series].filter(Boolean).join(' ')]];
 for(const [origin,text] of [['resumo',p.summary||''],['conteudo',p.content||'']])for(let pos=0;pos<text.length;pos+=360)phrases.push([origin,text.slice(pos,pos+480)]);
 const entries=phrases.filter(([,text])=>text).map(([origin,phrase])=>({origin,phrase,raw:normalize(phrase),pc:canonical(phrase),pt:tokens(canonical(phrase))}));searchIndex.set(p,entries);return entries;
}
export function rankProcedures(data,query){
 const q=normalize(query);if(!q)return data.map(p=>({...p,score:0}));const qc=canonical(q),qt=tokens(qc),useful=qt.filter(t=>!['nao','sem','nunca'].includes(t));if(!useful.length)return [];
 const neg=t=>t.some(x=>['nao','sem','nunca'].includes(x));
 return data.map(p=>{const titleTokens=tokens(canonical(p.title));let best={score:0,matchReason:'',matchedTerm:''};
 for(const {origin,phrase,raw,pc,pt} of phraseIndex(p)){
  if(!pt.length)continue;const body=['resumo','conteudo'].includes(origin),intent=body?pt:titleTokens;
  const opposite=(qt.includes('abre')&&intent.includes('fecha')&&!intent.includes('abre'))||(qt.includes('fecha')&&intent.includes('abre')&&!intent.includes('fecha'));
  const negDifferent=neg(qt)!==neg(intent)&&qt.some(x=>['nao','sem','nunca','abre','fecha'].includes(x));
  const coverage=useful.reduce((sum,t)=>sum+Math.max(0,...pt.map(w=>wordScore(t,w))),0)/useful.length;const sim=similarity(qc,pc);let score=0,reason='';
  if(q===raw){score=origin==='titulo'?100:origin==='alias'?98:91;reason='Correspondência exata: '+(origin==='titulo'?'título':origin==='alias'?'termo alternativo':origin)}
  else if(qc===pc){score=origin==='titulo'?96:origin==='alias'?95:89;reason='Expressão equivalente'}
  else if(JSON.stringify(qt)===JSON.stringify(pt)){score=93;reason='Mesmos termos em outra forma ou ordem'}
  else if(qt.every(t=>pt.includes(t))){score=86+4*qt.length/pt.length;reason='Todos os termos encontrados'}
  else if(coverage>=.65){score=Math.min(88,45+30*coverage+13*sim);reason='Palavras próximas ou erro de digitação'}
  else if(coverage>=.3){score=Math.min(68,20+30*coverage+18*sim);reason='Correspondência parcial'}
  if(negDifferent){score=Math.max(0,score-30);reason+='; negação diferente'}
  if(opposite){score=Math.min(44,Math.max(0,score-12));reason+='; ação diferente'}
  if(origin==='palavra_chave')score=Math.min(score,72);if(origin==='contexto')score=Math.min(score,85);
  if(body){score=Math.min(score,origin==='conteudo'?78:82);reason=(origin==='conteudo'?'Ocorrência no conteúdo completo; ':'Ocorrência no resumo; ')+reason;}
  if(score>best.score)best={score:Math.round(score*100)/100,matchReason:reason,matchedTerm:phrase};
 }
 return {...p,...best};}).filter(p=>p.score>=25).sort((a,b)=>b.score-a.score||a.title.localeCompare(b.title,'pt-BR')||a.id.localeCompare(b.id));
}
