import {readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2],vendor=resolve(process.argv[3]);
const {eastAsianWidth}=await import(join(vendor,'get-east-asian-width/index.js'));
const transpiler=new Bun.Transpiler({loader:'ts'});
const hashes:Record<string,string>={"src/utils.ts": "8cda2d53e2361ac5aaf6d7345b2fee058c8df5743eae4e4e90c89a7072c026c3", "src/keys.ts": "b972facce4233a4623239fc38029e28cae15d0fb326558c0c09dc02cf4345fa7", "src/keybindings.ts": "eea5e3fe258ad50337595bb5320955a6d97bac0c8f6c0a838f988d75079bcf38", "src/word-navigation.ts": "b73e915a524926ac8881731e89026b0bc7b5b0bd465de67257af81a420465c7f", "src/kill-ring.ts": "d829ae816560b12d2800a38db9f7278f76d9ef43d0e53e004a86add9b56c559a", "src/undo-stack.ts": "1373c1e0a1e2c58ac90c93d32a9e5c1226d7f53314c77dd3d0f8ec349d2b3627", "src/components/input.ts": "416ceeb28f10b7146f6a284f276589797763b604d439574fbdc2a3ca52c00234", "test/input.test.ts": "dcbed4da6d52e41dd52faaef9861ee4662806d5529e33b612f22e691e9a51386", "src/fuzzy.ts": "0ae2bedc6a4f043d875ec415202a6e3d9e45405741359d7d2dc2855240dff633", "src/components/settings-list.ts": "8d6b91d3c4aaaf11225854847d42ae6da852ef2646d54542c5b51a97dde15605", "test/settings-list.test.ts": "36418fe2495b92835c24a15129c5371f2dcffdfb72d0ecce7208b1ab0056062d"};
function source(path:string){const value=readFileSync(join(root,'packages/tui',path),'utf8');assert.equal(createHash('sha256').update(value).digest('hex'),hashes[path],path);return value;}
function compiled(path:string){return transpiler.transformSync(source(path).replace(/^import.*\n/gm,'')).replace(/\bexport /g,'');}
const utils=new Function('eastAsianWidth',compiled('src/utils.ts')+';return {getGraphemeSegmenter,isWhitespaceChar,sliceByColumn,truncateToWidth,visibleWidth,stripTerminalSequences,wrapTextWithAnsi,PUNCTUATION_REGEX};')(eastAsianWidth);
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
const {fuzzyFilter}=new Function(compiled('src/fuzzy.ts')+';return {fuzzyFilter};')();
const SourceSettings=new Function(...Object.keys(utils),'fuzzyFilter','getKeybindings','Input',compiled('src/components/settings-list.ts')+';return SettingsList;')(...Object.values(utils),fuzzyFilter,()=>manager,SourceInput);
let name='',instances:any[]=[];
let externalCompletions:Array<(value?:string,options?:{navigateTo?:string})=>void>=[];
let childCalls:any[]=[];
function childFactory(id:string,spec:any){
 const factory=(currentValue:string,done:any)=>{
  childCalls.push({kind:'open',id,currentValue});externalCompletions.push(done);
  return {
   render(width:number){childCalls.push({kind:'child-render',id,width});return [`submenu:${id}:${width}`];},
   invalidate(){childCalls.push({kind:'child-invalidate',id});},
   handleInput(data:string){childCalls.push({kind:'child-input',id,data});if(data==='save')done('selected:'+id);else if(data==='cancel')done();else if(data.startsWith('goto:'))done(undefined,{navigateTo:data.slice(5)});},
   handleMouse(event:any){childCalls.push({kind:'child-mouse',id,type:event.type,y:event.y});if(spec.mouse==='none')return undefined;if(spec.mouse==='unhandled')return {handled:false};return {handled:true,capture:spec.mouse==='capture',render:false};},
  };
 };
 factory.fixtureSpec=spec;return factory;
}
class TraceSettings extends SourceSettings{
 running=false;steps:any[]=[];observations:any[]=[];calls:any[];input:any;name:string;
 constructor(items:any,maxVisible:number,theme:any,onChange:any,onCancel:any,options:any={}){
  const calls:any[]=[];
  const wrapped={cursor:theme.cursor,...Object.fromEntries(['label','value','description','hint'].map(kind=>[kind,(text:string,selected?:boolean)=>{calls.push({kind,text,...(selected===undefined?{}:{selected})});return theme[kind](text,selected); }]))};
  super(items,maxVisible,wrapped,(id:string,value:string)=>{calls.push({kind:'change',id,value});onChange(id,value);},()=>{calls.push({kind:'cancel'});onCancel();},options);
  this.calls=calls;childCalls=calls;this.name=name;
  this.input={items:items.map((item:any)=>({...item,submenu:item.submenu?.fixtureSpec})),maxVisible,options,cursor:theme.cursor};
  instances.push(this);
 }
 perform(step:any){
  this.running=true;childCalls=this.calls;activeSegments={};let result:any;
  if(step.op==='input')super.handleInput(step.data);
  else if(step.op==='render')result=super.render(step.width);
  else if(step.op==='update')super.updateValue(step.id,step.value);
  else if(step.op==='select')super.selectItem(step.id);
  else if(step.op==='mouse')result=super.handleMouse(step.event);
  else if(step.op==='complete')externalCompletions[step.origin](step.value,step.navigateTo===undefined?undefined:{navigateTo:step.navigateTo});
  else super.invalidate();
  this.steps.push({...step,segments:activeSegments});
  const snapshot:any={items:this.items.map((item:any)=>({id:item.id,value:item.currentValue})),selected:this.getDisplayItems()[this.selectedIndex]?.id??null,search:this.searchInput?.getValue()??null,submenu:!!this.submenuComponent};
  if(step.op==='render')snapshot.lines=result;
  if(step.op==='mouse')snapshot.mouse=result?Object.fromEntries(Object.entries(result).filter(([key,value])=>!['capture','focus'].includes(key)||value)):null;
  this.observations.push(snapshot);this.running=false;return result;
 }
 handleInput(data:string){return this.perform({op:'input',data});}
 render(width:number){return this.perform({op:'render',width});}
 updateValue(id:string,value:string){return this.perform({op:'update',id,value});}
 selectItem(id:string){if(this.running)return super.selectItem(id);return this.perform({op:'select',id});}
 handleMouse(event:any){return this.perform({op:'mouse',event});}
 invalidate(){return this.perform({op:'invalidate'});}
 fixture(extra:any={}){return {name:this.name,input:{...this.input,steps:this.steps,...extra},expected:{observations:this.observations,calls:this.calls}};}
}
function query(v:any){
 keys.setKittyProtocolActive(!!v.kitty);manager=new KeybindingsManager(TUI_KEYBINDINGS,v.bindings||{});externalCompletions=[];
 const items=v.items.map((item:any)=>({...item,submenu:item.submenu?childFactory(item.id,item.submenu):undefined}));
 const theme={cursor:v.cursor??'> ',...Object.fromEntries(['label','value','description','hint'].map(kind=>[kind,(text:string)=>v.styled?`\x1b[31m${text}\x1b[39m`:text]))};
 const state=new TraceSettings(items,v.maxVisible??5,theme,()=>{},()=>{},v.options??{});
 for(const step of v.steps)state.perform(step);
 return state.fixture({styled:v.styled,kitty:v.kitty,bindings:v.bindings});
}
if(process.argv[4]==='--original'){
 const bindings={assert,SettingsList:TraceSettings,describe:(_:string,fn:()=>void)=>fn(),it:(label:string,fn:()=>void)=>{name=label;fn();}};
 new Function(...Object.keys(bindings),transpiler.transformSync(source('test/settings-list.test.ts').replace(/^import.*\n/gm,'')))(...Object.values(bindings));
 console.log(JSON.stringify(instances.map(input=>input.fixture())));
}else for(const arg of process.argv.slice(4))console.log(JSON.stringify(JSON.parse(arg).map(query)));
