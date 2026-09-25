import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join} from 'node:path';
import assert from 'node:assert/strict';
const root=process.argv[2];
for(const [file,hash] of [['src/utils.ts','8cda2d53e2361ac5aaf6d7345b2fee058c8df5743eae4e4e90c89a7072c026c3'],['test/truncate-to-width.test.ts','fd75a99d47ff465d56a1f3ede16e37ca7d29aa910e2322881e824e6c2937b7b8'],['test/tab-width.test.ts','59fff93aeecb3809f41f7bf68d88ef8ba9f0f38cd3a2db785a1f16a0ac114419']])assert.equal(createHash('sha256').update(readFileSync(join(root,'packages/tui',file))).digest('hex'),hash);
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
