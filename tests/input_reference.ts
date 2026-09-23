import {readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2],vendor=resolve(process.argv[3]);
const {eastAsianWidth}=await import(join(vendor,'get-east-asian-width/index.js'));
const transpiler=new Bun.Transpiler({loader:'ts'});
const hashes:Record<string,string>={"src/utils.ts": "014e017a0cb45d8f4e07af6e472c282c6dec7c5856a335a3e3beeb6054f385d3", "src/keys.ts": "b972facce4233a4623239fc38029e28cae15d0fb326558c0c09dc02cf4345fa7", "src/keybindings.ts": "eea5e3fe258ad50337595bb5320955a6d97bac0c8f6c0a838f988d75079bcf38", "src/word-navigation.ts": "b73e915a524926ac8881731e89026b0bc7b5b0bd465de67257af81a420465c7f", "src/kill-ring.ts": "d829ae816560b12d2800a38db9f7278f76d9ef43d0e53e004a86add9b56c559a", "src/undo-stack.ts": "1373c1e0a1e2c58ac90c93d32a9e5c1226d7f53314c77dd3d0f8ec349d2b3627", "src/components/input.ts": "416ceeb28f10b7146f6a284f276589797763b604d439574fbdc2a3ca52c00234", "test/input.test.ts": "dcbed4da6d52e41dd52faaef9861ee4662806d5529e33b612f22e691e9a51386"};
function source(path:string){const value=readFileSync(join(root,'packages/tui',path),'utf8');assert.equal(createHash('sha256').update(value).digest('hex'),hashes[path],path);return value;}
function compiled(path:string){return transpiler.transformSync(source(path).replace(/^import.*\n/gm,'')).replace(/\bexport /g,'');}
const utils=new Function('eastAsianWidth',compiled('src/utils.ts')+';return {getGraphemeSegmenter,isWhitespaceChar,sliceByColumn,truncateToWidth,visibleWidth,stripTerminalSequences,PUNCTUATION_REGEX};')(eastAsianWidth);
const keys=new Function(compiled('src/keys.ts')+';return {matchesKey,decodeKittyPrintable,setKittyProtocolActive};')();
const {KeybindingsManager,TUI_KEYBINDINGS}=new Function(...Object.keys(keys),compiled('src/keybindings.ts')+';return {KeybindingsManager,TUI_KEYBINDINGS};')(...Object.values(keys));
let manager=new KeybindingsManager(TUI_KEYBINDINGS,{});
let activeSegments:Record<string,any[]>={};
const wordSegmenter=new Intl.Segmenter(undefined,{granularity:'word'});
const getWordSegmenter=()=>({segment(text:string){const parts=[...wordSegmenter.segment(text)];activeSegments[text]=parts.map(p=>[p.segment,!!p.isWordLike]);return parts;}});
const navigation=new Function(...Object.keys(utils),'getWordSegmenter',compiled('src/word-navigation.ts')+';return {findWordBackward,findWordForward};')(...Object.values(utils),getWordSegmenter);
const {KillRing}=new Function(compiled('src/kill-ring.ts')+';return {KillRing};')();
const {UndoStack}=new Function(compiled('src/undo-stack.ts')+';return {UndoStack};')();
const SourceInput=new Function(...Object.keys(utils),...Object.keys(navigation),'decodeKittyPrintable','getKeybindings','KillRing','UndoStack','CURSOR_MARKER',compiled('src/components/input.ts')+';return Input;')(...Object.values(utils),...Object.values(navigation),keys.decodeKittyPrintable,()=>manager,KillRing,UndoStack,'\x1b_pi:c\x07');
let name='',instances:any[]=[];
class TraceInput extends SourceInput {
 steps:any[]=[];observations:any[]=[];calls:any[];options:any;depth=0;name:string;
 constructor(options:any={}){
  const calls:any[]=[];
  super({...options,placeholderStyle:options.placeholderStyle?(text:string)=>{calls.push({kind:'style',text});return options.placeholderStyle(text);}:undefined});
  this.calls=calls;this.name=name;
  this.options={prompt:options.prompt,placeholder:options.placeholder,style:options.placeholderStyle?'dim':undefined};
  instances.push(this);
 }
 perform(op:string,value:any){
  const step:any={op,focused:this.focused};
  if(op==='input')step.data=value;
  if(op==='set')step.value=value;
  if(op==='render')step.width=value;
  if(op==='mouse')step.event=value;
  activeSegments={};
  const submit=this.onSubmit,escape=this.onEscape;
  this.onSubmit=(value:string)=>{this.calls.push({kind:'submit',value});submit?.(value);};
  this.onEscape=()=>{this.calls.push({kind:'escape'});escape?.();};
  let result:any;this.depth++;
  try{
   if(op==='input')super.handleInput(value);
   else if(op==='set')super.setValue(value);
   else if(op==='render')result=super.render(value);
   else if(op==='mouse')result=super.handleMouse(value);
   else super.invalidate();
  }finally{this.depth--;this.onSubmit=submit;this.onEscape=escape;}
  step.segments=activeSegments;
  this.steps.push(step);
  const snapshot:any={value:super.getValue(),cursor:[...super.getValue().slice(0,this.cursor)].length};
  if(op==='render')snapshot.lines=result;
  if(op==='mouse')snapshot.mouse=result??null;
  this.observations.push(snapshot);
  return result;
 }
 handleInput(data:string){if(this.depth)return super.handleInput(data);return this.perform('input',data);}
 setValue(value:string){return this.perform('set',value);}
 render(width:number){return this.perform('render',width);}
 handleMouse(event:any){return this.perform('mouse',event);}
 invalidate(){return this.perform('invalidate',null);}
 fixture(extra:any={}){return {name:this.name,input:{options:this.options,steps:this.steps,...extra},expected:{observations:this.observations,calls:this.calls}};}
}
function query(v:any){
 keys.setKittyProtocolActive(!!v.kitty);
 manager=new KeybindingsManager(TUI_KEYBINDINGS,v.bindings||{});
 const input=new TraceInput({...v.options,placeholderStyle:v.options?.style?(text:string)=>`\x1b[2m${text}\x1b[22m`:undefined});
 for(const step of v.steps){input.focused=!!step.focused;input.perform(step.op,step.op==='input'?step.data:step.op==='set'?step.value:step.op==='render'?step.width:step.event);}
 return input.fixture({kitty:v.kitty,bindings:v.bindings});
}
if(process.argv[4]==='--original'){
 const bindings={assert,Input:TraceInput,stripTerminalSequences:utils.stripTerminalSequences,visibleWidth:utils.visibleWidth,describe:(_:string,fn:()=>void)=>fn(),it:(label:string,fn:()=>void)=>{name=label;fn();}};
 new Function(...Object.keys(bindings),transpiler.transformSync(source('test/input.test.ts').replace(/^import.*\n/gm,'')))(...Object.values(bindings));
 console.log(JSON.stringify(instances.map(input=>input.fixture())));
}else for(const arg of process.argv.slice(4))console.log(JSON.stringify(JSON.parse(arg).map(query)));
