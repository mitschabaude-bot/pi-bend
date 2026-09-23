import fs from 'node:fs';
import path from 'node:path';
import {EventEmitter} from 'node:events';
import {stripTypeScriptTypes} from 'node:module';
const text=stripTypeScriptTypes(fs.readFileSync('../pi-mono/packages/tui/src/terminal.ts','utf8')).replace(/^import .*;$/gm,'').replace(/^export /gm,'');
let now=0,timers=[];
const stdout=new EventEmitter(),stdin=new EventEmitter();
let writes=[],input=[];stdout.write=x=>{writes.push(x);return true};stdin.pause=()=>{};
const proc={platform:'linux',env:{},stdout,stdin,pid:123,kill(){}};
const timeout=(fn,ms)=>{const t={fn,at:now+ms,cancelled:false};timers.push(t);return t};
const cancel=t=>{if(t)t.cancelled=true};
const source=new Function('process','fs','path','StdinBuffer','setKittyProtocolActive','isNativeModifierPressed','getNativePlatformHelper','setTimeout','clearTimeout','setInterval','clearInterval',text+';return ProcessTerminal;');
const Terminal=source(proc,fs,path,class{},()=>{},()=>false,()=>undefined,timeout,cancel,timeout,cancel);
const scenarios=JSON.parse(fs.readFileSync(0,'utf8'));
const result=scenarios.map(steps=>{
 now=0;timers=[];const terminal=new Terminal();terminal.keyboardProtocolPushed=true;terminal.inputHandler=x=>input.push(x);
 return steps.map(step=>{
   writes=[];input=[];
   if(Array.isArray(step)){
     now=step[0];const sequence=step[1];
     const negotiation=terminal.readKeyboardProtocolNegotiationSequence(sequence);
     if(negotiation==='pending') terminal.scheduleKeyboardProtocolNegotiationBufferFlush();
     else if(!terminal.handleKeyboardProtocolNegotiationSequence(negotiation))terminal.forwardInputSequence(sequence);
   }else if(typeof step==='number'){
     now=step;for(const timer of timers)if(!timer.cancelled&&timer.at<=now){timer.cancelled=true;timer.fn()}
   }else{
     terminal.clearKeyboardProtocolNegotiationBuffer();
     if(terminal.keyboardProtocolPushed||terminal.kittyProtocolActive){writes.push('\x1b[<u');terminal.keyboardProtocolPushed=false;terminal._kittyProtocolActive=false}
     terminal.disableModifyOtherKeys();
   }
   return {kitty:terminal.kittyProtocolActive,modify:terminal.modifyOtherKeysActive,pending:terminal.keyboardProtocolNegotiationBuffer,input,output:writes.join('')};
 });
});
console.log(JSON.stringify(result));
