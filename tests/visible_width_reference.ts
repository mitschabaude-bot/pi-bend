import {readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2],{eastAsianWidth}=await import(resolve(process.argv[3]));
const transpiler=new Bun.Transpiler({loader:'ts'});
const hashes:Record<string,string>={
 'packages/tui/src/utils.ts':'8cda2d53e2361ac5aaf6d7345b2fee058c8df5743eae4e4e90c89a7072c026c3',
 'packages/tui/test/truncate-to-width.test.ts':'fd75a99d47ff465d56a1f3ede16e37ca7d29aa910e2322881e824e6c2937b7b8',
 'packages/tui/test/wrap-ansi.test.ts':'9c238d85ad676ca6d4e063caa8d44d493b0c220dd9aba9ea11a31d51c92d791d',
 'packages/tui/test/regression-regional-indicator-width.test.ts':'a057bc5b61cd287e2f2f554e878222ebace84a515e6cf67b87191eba5c91ae47',
 'packages/tui/test/tab-width.test.ts':'59fff93aeecb3809f41f7bf68d88ef8ba9f0f38cd3a2db785a1f16a0ac114419',
};
function pinned(file:string){const text=readFileSync(join(root,file),'utf8');assert.equal(createHash('sha256').update(text).digest('hex'),hashes[file],file);return text;}
const sourceText=pinned('packages/tui/src/utils.ts');
const compiled=transpiler.transformSync(sourceText.replace(/^import.*\n/, '')).replace(/\bexport /g,'');
const names=['visibleWidth','graphemeWidth','normalizeTerminalOutput','truncateToWidth','wrapTextWithAnsi','extractSegments','sliceWithWidth'];
const source=new Function('eastAsianWidth',compiled+';return {'+names.join(',')+'};')(eastAsianWidth);
function propertyDigest(){let hash=2166136261;const mark=/^\p{Mark}$/u,spacing=/^\p{Spacing_Mark}$/u,control=/^[\p{Control}\p{Surrogate}]$/u,format=/^\p{Format}$/u,ignore=/^\p{Default_Ignorable_Code_Point}$/u,rgi=/^\p{RGI_Emoji}$/v;for(let cp=0;cp<0x110000;cp++){const text=String.fromCodePoint(cp);const bits=(mark.test(text)?1:0)|(spacing.test(text)?2:0)|(control.test(text)?4:0)|(format.test(text)?8:0)|(ignore.test(text)?16:0)|(eastAsianWidth(cp)===2?32:0)|(rgi.test(text)?64:0);hash=Math.imul(hash^bits,16777619)>>>0;}return hash;}
if(process.argv[4]==='--original'){
 const calls:any[]=[];const executed:string[]=[];let current='';const stack:string[]=[];
 const bindings:any={assert,...source,describe:(name:string,fn:()=>void)=>{stack.push(name);fn();stack.pop();},it:(name:string,fn:()=>void)=>{current=[...stack,name].join(' / ');executed.push(current);fn();}};
 bindings.visibleWidth=(text:string)=>{const expected=source.visibleWidth(text);calls.push({name:current,input:{method:'width',text},expected});return expected;};
 for(const file of ['truncate-to-width.test.ts','wrap-ansi.test.ts','regression-regional-indicator-width.test.ts']){
  const text=pinned('packages/tui/test/'+file).replace(/^import.*\n/gm,'');new Function(...Object.keys(bindings),transpiler.transformSync(text))(...Object.values(bindings));
 }
 const tabs=pinned('packages/tui/test/tab-width.test.ts');
 for(const name of ['keeps slice helper widths consistent with visible width','keeps overlay segment widths consistent with visible width']){
  const marker=`it("${name}", () => {`;const start=tabs.indexOf(marker);assert(start>=0);const end=tabs.indexOf('\n\t});',start);current='tab width accounting / '+name;executed.push(current);new Function(...Object.keys(bindings),transpiler.transformSync(tabs.slice(start+marker.length,end)))(...Object.values(bindings));
 }
 console.log(JSON.stringify({calls,executed}));
}else for(const arg of process.argv.slice(4))console.log(JSON.stringify(JSON.parse(arg).map((v:any)=>v.method==='properties'?propertyDigest():v.method==='emoji'?/^\p{RGI_Emoji}$/v.test(v.text):source[v.method==='grapheme'?'graphemeWidth':'visibleWidth'](v.text))));
