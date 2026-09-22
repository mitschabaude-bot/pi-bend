import {readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import assert from 'node:assert/strict';
const root=process.argv[2];
const {eastAsianWidth}=await import(resolve(process.argv[3]));
const transpiler=new Bun.Transpiler({loader:'ts'});
const raw=readFileSync(join(root,'packages/tui/src/utils.ts'),'utf8');
const code=transpiler.transformSync(raw.replace(/^import.*\n/, '')).replace(/\bexport /g,'');
const source=new Function('eastAsianWidth',code+';return {extractAnsiCode,stripTerminalSequences,normalizeTerminalOutput,getActiveBackgroundAnsi,getActiveOsc8Close,AnsiCodeTracker,updateTrackerFromText,visibleWidth};')(eastAsianWidth);
const snapshot=(s:any)=>({codes:s.getActiveCodes(),background:s.getActiveBackgroundCode(),reset:s.getLineEndReset(),active:s.hasActiveCodes()});
function query(input:any){
 if(input.method==='track'){const s=new source.AnsiCodeTracker();return input.items.map((text:any)=>{if(text===null)s.clear();else source.updateTrackerFromText(text,s);return snapshot(s);});}
 if(input.method==='extract'){const pos=Array.from(input.text).slice(0,input.position??0).join('').length;const result=source.extractAnsiCode(input.text,pos);return result?{code:result.code,length:Array.from(result.code).length}:null;}
 return source[{strip:'stripTerminalSequences',normalize:'normalizeTerminalOutput',background:'getActiveBackgroundAnsi',close:'getActiveOsc8Close'}[input.method]](input.text);
}
if(process.argv[4]==='--original'){
 const cases:any[]=[];
 for(const [file,name] of [['truncate-to-width.test.ts','normalizes Thai and Lao AM vowels only for terminal output'],['tab-width.test.ts','keeps tabs inside terminal control sequences byte-identical']]){
  const tests=readFileSync(join(root,'packages/tui/test',file),'utf8');const marker=`it("${name}", () => {`;const start=tests.indexOf(marker);assert(start>=0);const end=tests.indexOf('\n\t});',start);const body=tests.slice(start+marker.length,end);
  const normalize=(text:string)=>{const result=source.normalizeTerminalOutput(text);cases.push({name,input:{method:'normalize',text},expected:result});return result;};
  new Function('assert','normalizeTerminalOutput','visibleWidth',transpiler.transformSync(body))(assert,normalize,source.visibleWidth);
 }
 console.log(JSON.stringify(cases));
}else for(const arg of process.argv.slice(4))console.log(JSON.stringify(JSON.parse(arg).map(query)));
