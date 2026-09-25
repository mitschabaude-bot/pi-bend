import {readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2],vendor=resolve(process.argv[3]);
const {eastAsianWidth}=await import(join(vendor,'get-east-asian-width/index.js'));
const {Chalk}=await import(join(vendor,'chalk/source/index.js'));
const transpiler=new Bun.Transpiler({loader:'ts'});
const hashes:Record<string,string>={
 'src/utils.ts':'8cda2d53e2361ac5aaf6d7345b2fee058c8df5743eae4e4e90c89a7072c026c3',
 'src/components/text.ts':'3042e09dd8dcb870c23506e6fafb2dfcc095e7e375adad2fb62e447da17e5e3b',
 'src/components/truncated-text.ts':'c383487099d1864b51493a5838dd28a1bd3e5e440a675ec1dbcaf0177534fad0',
 'test/truncated-text.test.ts':'ba67883169e19dcb2013498d4b6659daa82b63daf01399f8471dc2b88b598141',
};
function source(path:string){const value=readFileSync(join(root,'packages/tui',path),'utf8');assert.equal(createHash('sha256').update(value).digest('hex'),hashes[path],path);return value;}
function compiled(path:string){return transpiler.transformSync(source(path).replace(/^import.*\n/gm,'')).replace(/\bexport /g,'');}
const utils=new Function('eastAsianWidth',compiled('src/utils.ts')+';return {visibleWidth,wrapTextWithAnsi,truncateToWidth,applyBackgroundToLine};')(eastAsianWidth);
const Text=new Function(...Object.keys(utils),compiled('src/components/text.ts')+';return Text;')(...Object.values(utils));
const TruncatedText=new Function(...Object.keys(utils),compiled('src/components/truncated-text.ts')+';return TruncatedText;')(...Object.values(utils));
function query(v:any){
 const calls:any[]=[],renders:any[]=[];
 const background=(kind:string)=>!kind||kind==='none'?undefined:(text:string)=>{calls.push({kind,text});return kind==='counter'?`[${calls.length}]${text}`:`\x1b[${kind==='red'?'41':'44'}m${text}\x1b[49m`;};
 if(v.component==='truncated'){const state=new TruncatedText(v.text,v.paddingX,v.paddingY);state.invalidate();renders.push(state.render(v.width));}
 else {
  const state=new Text(v.text,v.paddingX,v.paddingY,background(v.background));
  for(const action of v.steps?.length?v.steps:[{op:'render',width:v.width}]){
   if(action.op==='render')renders.push(state.render(action.width));
   else if(action.op==='text')state.setText(action.text);
   else if(action.op==='background')state.setCustomBgFn(background(action.kind));
   else state.invalidate();
  }
 }
 return {renders,calls};
}
if(process.argv[4]==='--original'){
 const calls:any[]=[];let name='';
 class Tracked extends TruncatedText {input:any;constructor(text:string,paddingX?:number,paddingY?:number){super(text,paddingX,paddingY);this.input={component:'truncated',text,paddingX,paddingY};}render(width:number){const result=super.render(width);calls.push({name,input:{...this.input,width},expected:{renders:[result],calls:[]}});return result;}}
 const bindings={assert,Chalk,TruncatedText:Tracked,visibleWidth:utils.visibleWidth,describe:(_name:string,fn:()=>void)=>fn(),it:(label:string,fn:()=>void)=>{name=label;fn();}};
 new Function(...Object.keys(bindings),transpiler.transformSync(source('test/truncated-text.test.ts').replace(/^import.*\n/gm,'')))(...Object.values(bindings));
 console.log(JSON.stringify(calls));
}else for(const arg of process.argv.slice(4))console.log(JSON.stringify(JSON.parse(arg).map(query)));
