import { readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2], vendor=resolve(process.argv[3]);
const {eastAsianWidth}=await import(join(vendor,'get-east-asian-width/index.js'));
const transpiler=new Bun.Transpiler({loader:'ts'});
const hashes:Record<string,string>={"src/utils.ts": "8cda2d53e2361ac5aaf6d7345b2fee058c8df5743eae4e4e90c89a7072c026c3", "src/keys.ts": "b972facce4233a4623239fc38029e28cae15d0fb326558c0c09dc02cf4345fa7", "src/keybindings.ts": "eea5e3fe258ad50337595bb5320955a6d97bac0c8f6c0a838f988d75079bcf38", "src/components/select-list.ts": "0fc369801e745eff15567d72829bf67887f5efec8bc6816aaf1ee65338618373", "test/select-list.test.ts": "0135b531ef8dfe52de6625c2004a4ed95566214bc9860068106c862efcf22376"};
function source(path:string){const value=readFileSync(join(root,'packages/tui',path),'utf8'); assert.equal(createHash('sha256').update(value).digest('hex'),hashes[path],path); return value;}
function compiled(path:string){return transpiler.transformSync(source(path).replace(/^import.*\n/gm,'')).replace(/\bexport /g,'');}
const utils=new Function('eastAsianWidth',compiled('src/utils.ts')+';return {visibleWidth,truncateToWidth};')(eastAsianWidth);
const keys=new Function(compiled('src/keys.ts')+';return {matchesKey,setKittyProtocolActive};')();
const {KeybindingsManager,TUI_KEYBINDINGS}=new Function(...Object.keys(keys),compiled('src/keybindings.ts')+';return {KeybindingsManager,TUI_KEYBINDINGS};')(...Object.values(keys));
let keybindings:any;
const SelectList=new Function(...Object.keys(utils),'getKeybindings',compiled('src/components/select-list.ts')+';return SelectList;')(...Object.values(utils),()=>keybindings);
const identityTheme=Object.fromEntries(['selectedPrefix','selectedText','description','scrollInfo','noMatch'].map(kind=>[kind,(text:string)=>text]));
const ellipsis=({text,maxWidth}:any)=>text.length<=maxWidth?text:`${text.slice(0,Math.max(0,maxWidth-1))}…`;
function query(v:any){
 const calls:any[]=[],observations:any[]=[];
 keys.setKittyProtocolActive(!!v.kitty);
 keybindings=new KeybindingsManager(TUI_KEYBINDINGS,v.bindings||{});
 const theme=Object.fromEntries(Object.keys(identityTheme).map(kind=>[kind,(text:string)=>{calls.push({kind,text});return v.styled?`\x1b[31m${text}\x1b[39m`:text;}]));
 const layout={...v.layout};
 if(v.primary)layout.truncatePrimary=(context:any)=>{calls.push({kind:'truncatePrimary',...context}); return v.primary==='ellipsis'?ellipsis(context):v.primary==='overflow'?context.text+' extra primary text':context.text;};
 const state=new SelectList(v.items,v.maxVisible??5,theme,layout);
 if(v.events!=='none'){
 state.onSelect=(item:any)=>calls.push({kind:'select',item});
 state.onSelectionChange=(item:any)=>calls.push({kind:'change',item});
 state.onCancel=()=>calls.push({kind:'cancel'});
 }
 for(const step of v.steps||[{op:'render',width:v.width??80}]){
  if(step.op==='render')observations.push({lines:state.render(step.width)});
  else if(step.op==='filter')state.setFilter(step.filter);
  else if(step.op==='index')state.setSelectedIndex(step.index);
  else if(step.op==='input')state.handleInput(step.data);
  else if(step.op==='mouse')observations.push({mouse:state.handleMouse(step.event)??null});
  else state.invalidate();
  observations.push({selected:state.getSelectedItem()});
 }
 return {observations,calls};
}
if(process.argv[4]==='--original'){
 const cases:any[]=[];let name='';
 class Tracked extends SelectList {input:any;constructor(items:any,maxVisible:any,theme:any,layout:any){super(items,maxVisible,theme,layout);this.input={items,maxVisible,layout,primary:layout?.truncatePrimary?'ellipsis':undefined};}render(width:number){const lines=super.render(width);const input={...this.input,width};const expected=query(input);assert.deepEqual(expected.observations[0].lines,lines);cases.push({name,input,expected});return lines;}}
 const bindings={assert,SelectList:Tracked,visibleWidth:utils.visibleWidth,describe:(_:string,fn:()=>void)=>fn(),it:(label:string,fn:()=>void)=>{name=label;fn();}};
 new Function(...Object.keys(bindings),transpiler.transformSync(source('test/select-list.test.ts').replace(/^import.*\n/gm,'')))(...Object.values(bindings));
 console.log(JSON.stringify(cases));
}else for(const arg of process.argv.slice(4))console.log(JSON.stringify(JSON.parse(arg).map(query)));
