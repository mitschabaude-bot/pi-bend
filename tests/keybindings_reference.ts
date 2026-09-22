import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import assert from 'node:assert/strict';
const root=process.argv[2], transpiler=new Bun.Transpiler({loader:'ts'});
const compile=(path:string)=>transpiler.transformSync(readFileSync(join(root,path),'utf8').replace(/^import[^\n]*\n/gm,'')).replace(/\bexport /g,'');
const keyboard=new Function(compile('packages/tui/src/keys.ts')+';return {matchesKey,setKittyProtocolActive};')();
const source=new Function('matchesKey',compile('packages/tui/src/keybindings.ts')+';return {KeybindingsManager,TUI_KEYBINDINGS};')(keyboard.matchesKey);
function key(value:string){const parts=value.toLowerCase().split('+');let base=parts.pop()!;const modifiers=new Set(parts);const names:any={pageup:'pageUp',pagedown:'pageDown',esc:'escape',return:'enter'};return ['shift','ctrl','alt','super'].filter(x=>modifiers.has(x)).map(x=>x+'+').join('')+(names[base]??base);}
const list=(value:any)=>value===undefined?[]:(Array.isArray(value)?value:[value]).map(key);
function normalize(method:string,value:any):any{
 if(method==='getKeys')return list(value);
 if(method==='getConflicts')return value.map((v:any)=>({...v,key:key(v.key)}));
 if(method==='getUserBindings'||method==='getResolvedBindings')return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,list(v)]));
 if(method==='getDefinition')return value?{defaultKeys:list(value.defaultKeys),description:value.description??null}:null;
 return value??null;
}
function configure(input:any){keyboard.setKittyProtocolActive(input.kitty??false);for(const name of ['WT_SESSION','SSH_CONNECTION','SSH_CLIENT','SSH_TTY'])delete process.env[name];if(input.windows)process.env.WT_SESSION='keybindings-test';}
function invoke(manager:any,input:any){configure(input);return normalize(input.method,input.method==='matches'?manager.matches(input.data,input.action):manager[input.method](input.action));}
if(process.argv[3]==='--original'){
 const cases:any[]=[];let current='';const stack:string[]=[];
 class Traced extends source.KeybindingsManager{
  config:any;constructor(definitions:any,config:any={}){super(definitions,config);this.config=config;}
 }
 for(const method of ['getKeys','getConflicts','getDefinition','getUserBindings','getResolvedBindings','matches']){
  Traced.prototype[method]=function(...args:any[]){const value=source.KeybindingsManager.prototype[method].apply(this,args);const query={method,...(method==='matches'?{data:args[0],action:args[1]}:{action:args[0]})};cases.push({name:current,input:{bindings:this.config,steps:[{queries:[query]}]},expected:[[normalize(method,value)]]});return value;};
 }
 const bindings:any={assert,KeybindingsManager:Traced,TUI_KEYBINDINGS:source.TUI_KEYBINDINGS,describe:(name:string,fn:()=>void)=>{stack.push(name);fn();stack.pop();},it:(name:string,fn:()=>void)=>{current=[...stack,name].join(' / ');fn();}};
 new Function(...Object.keys(bindings),compile('packages/tui/test/keybindings.test.ts'))(...Object.values(bindings));
 console.log(JSON.stringify(cases));
}else if(process.argv[3]==='--definitions')console.log(JSON.stringify(source.TUI_KEYBINDINGS));
else for(const argument of process.argv.slice(3))console.log(JSON.stringify(JSON.parse(argument).map((input:any)=>{const manager=new source.KeybindingsManager(input.definitions??source.TUI_KEYBINDINGS,input.bindings??{});return input.steps.map((step:any)=>{if(step.replace)manager.setUserBindings(step.replace);return step.queries.map((q:any)=>invoke(manager,q));});})));
