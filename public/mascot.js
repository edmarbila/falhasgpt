const lines={
 greeting:['Seja bem-vindo! Vamos explorar o conhecimento?','Olá! Sou a CharleIA. Vamos colocar a locomotiva nos trilhos do conhecimento?','Embarque por aqui! Qual conhecimento vamos explorar hoje?'],
 ready:['Estou pronta para ajudar novamente! Qual é a próxima dúvida?','Um belo dia para aprender. Vamos para a próxima parada?','Conhecimento a bordo! Para onde vamos agora?','Próxima parada: uma nova descoberta. Pode perguntar!'],
 searching:['Vamos procurar uma pista no acervo…','Consultando os trilhos do conhecimento…','Deixe-me conferir os documentos para você…'],
 sad:['Que pena! Espero ajudar com os próximos conteúdos. Podemos tentar outra descrição?','Ainda não chegamos à estação certa. Vamos tentar outros termos?','Esse conhecimento ainda pode estar a caminho. Que tal explorar outro assunto?'],
 cheerful:['Encontrei algumas pistas! Confira o resultado mais próximo.','Conhecimento à vista! Vamos conferir os documentos?','Chegamos a alguns resultados. Veja qual atende à sua dúvida.'],
 success:['Que bom que ajudei! Conhecimento que segue viagem.','Missão cumprida! Pronta para a próxima descoberta.','Mais uma dúvida ficou na estação. Vamos em frente!']
};
const esc=s=>s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let visited=false;try{visited=sessionStorage.getItem('fgpt-charleia-welcomed')==='yes';sessionStorage.setItem('fgpt-charleia-welcomed','yes');}catch{}
const previous={};let event=visited?'ready':'greeting',started=performance.now(),phrase='',settleTimer,idleTimer;
const duration=2200;
function choose(key){const choices=lines[key];let n=Math.floor(Math.random()*choices.length);if(n===previous[key])n=(n+1)%choices.length;previous[key]=n;return choices[n];}
phrase=choose(event);
function snapshot(){const elapsed=performance.now()-started,active=elapsed<duration;const resting=event==='sad'?'sad':event==='searching'?'searching':'idle';return {state:active?(event==='ready'?'cheerful':event):resting,active,elapsed};}
export function setMascotEvent(next){if(!lines[next])return;event=next;started=performance.now();phrase=choose(next);clearTimeout(idleTimer);syncMascots();}
export function mascot(_legacyState,size='normal',speech=false){const s=snapshot();return `<div class="charleia ${size}" data-state="${s.state}" data-event="${event}" data-active="${s.active}"><span class="charleia-frame" role="img" aria-label="CharleIA" style="--gesture-delay:-${Math.min(duration,s.elapsed)}ms"></span>${speech?`<p class="charleia-speech">${esc(phrase)}</p>`:''}</div>`;}
function scheduleIdle(){if(idleTimer)return;idleTimer=setTimeout(()=>{idleTimer=null;const s=snapshot();if(!document.hidden&&!s.active&&!['sad','searching'].includes(event)&&!document.activeElement?.matches('input,textarea')&&!matchMedia('(prefers-reduced-motion: reduce)').matches){document.querySelectorAll('.charleia-frame').forEach(el=>el.animate([{transform:'translateY(0) rotate(0)'},{transform:'translateY(-2px) rotate(-1deg)',offset:.45},{transform:'translateY(0) rotate(0)'}],{duration:1800,easing:'ease-in-out'}));}scheduleIdle();},28000+Math.random()*17000);}
export function syncMascots(){const s=snapshot();document.querySelectorAll('.charleia').forEach(el=>{el.dataset.state=s.state;el.dataset.event=event;el.dataset.active=String(s.active);el.querySelector('.charleia-frame')?.style.setProperty('--gesture-delay',`-${Math.min(duration,s.elapsed)}ms`);const bubble=el.querySelector('.charleia-speech');if(bubble)bubble.textContent=phrase;});clearTimeout(settleTimer);if(s.active)settleTimer=setTimeout(syncMascots,Math.max(10,duration-s.elapsed+20));scheduleIdle();}
