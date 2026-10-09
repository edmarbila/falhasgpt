export function normalizeRE(value){const v=String(value??'').trim().replace(/[- ]/g,'');return /^59\d{5}$/.test(v)?'59-'+v.slice(2):null;}
export function extractREs(cells){
 const unique=new Set();let occurrences=0,ignored=0;
 for(const value of cells){
  const text=String(value??'').trim();if(!text)continue;
  const matches=[...text.matchAll(/(?<![0-9A-Za-z])59(?:[- ]?)[0-9]{5}(?![0-9A-Za-z])/g)].map(m=>normalizeRE(m[0])).filter(Boolean);
  if(!matches.length){ignored++;continue;}
  for(const re of matches){occurrences++;unique.add(re);}
 }
 return {res:[...unique].sort(),duplicates:occurrences-unique.size,ignored};
}
let sheetScript;
function sheetJS(){if(window.XLSX)return Promise.resolve(window.XLSX);return sheetScript??=new Promise((resolve,reject)=>{const s=document.createElement('script');s.src=new URL('./vendor/xlsx.full.min.js',import.meta.url).href;s.onload=()=>resolve(window.XLSX);s.onerror=()=>{sheetScript=null;reject(new Error('Não foi possível abrir o leitor de planilhas.'));};document.head.append(s);});}
export async function readREFile(file){
 if(file.size>10*1024*1024)throw new Error('A planilha deve ter até 10 MB.');
 if(!/\.(xlsx|xls|csv)$/i.test(file.name))throw new Error('Selecione uma planilha XLSX, XLS ou CSV.');
 const XLSX=await sheetJS();const wb=XLSX.read(await file.arrayBuffer(),{type:'array',sheetRows:50001,cellFormula:false,cellHTML:false,cellNF:false});
 if(wb.SheetNames.length>30)throw new Error('Use uma planilha com até 30 abas.');
 const cells=[];
 for(const name of wb.SheetNames){const sheet=wb.Sheets[name];if(sheet['!fullref'])throw new Error('Uma aba excedeu 50 mil linhas. Divida a planilha.');const rows=XLSX.utils.sheet_to_json(sheet,{header:1,raw:true,defval:''});for(const row of rows){cells.push(...row);if(cells.length>200000)throw new Error('A planilha é muito grande. Divida em arquivos menores.');}}
 const result=extractREs(cells);if(result.res.length>5000)throw new Error('Importe até 5.000 REs por vez.');return result;
}
export async function validatePDF(file){
 if(file.size===0||file.size>20*1024*1024)throw new Error('Cada PDF deve ter entre 1 byte e 20 MB.');
 const head=new TextDecoder().decode(await file.slice(0,8).arrayBuffer());if(!file.name.toLowerCase().endsWith('.pdf')||!head.startsWith('%PDF-'))throw new Error('Selecione um arquivo PDF válido.');
}
export async function extractPDF(file,onProgress=()=>{}){
 await validatePDF(file);
 const pdfjs=await import('./vendor/pdfjs/pdf.mjs');pdfjs.GlobalWorkerOptions.workerSrc=new URL('./vendor/pdfjs/pdf.worker.mjs',import.meta.url).href;
 const task=pdfjs.getDocument({data:new Uint8Array(await file.arrayBuffer()),isEvalSupported:false,disableFontFace:true});
 let pdf;try{
  pdf=await task.promise;if(pdf.numPages>300)throw new Error('Este PDF tem mais de 300 páginas. Separe por procedimento antes de importar.');
  let text='';
  for(let pageNumber=1;pageNumber<=pdf.numPages;pageNumber++){
   onProgress(pageNumber,pdf.numPages);const page=await pdf.getPage(pageNumber);const content=await page.getTextContent();
   let pageText='';for(const item of content.items)if(typeof item.str==='string')pageText+=item.str+(item.hasEOL?'\n':' ');
   text+='\n\n[Página '+pageNumber+']\n'+pageText.trim();page.cleanup();
   if(text.length>2000000)throw new Error('O texto excedeu 2 milhões de caracteres. Divida o documento.');
  }
  const useful=text.replace(/\[Página \d+\]/g,'').trim();return {text:useful.length>20?text.trim():'',pages:pdf.numPages,scanned:useful.length<=20};
 }catch(e){if(e.name==='PasswordException')throw new Error('O PDF está protegido por senha. Envie uma cópia acessível.');if(e.name==='InvalidPDFException')throw new Error('Não foi possível ler este PDF. Confira o arquivo.');throw e;}finally{await task.destroy();}
}
