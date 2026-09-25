import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {EventEmitter} from 'node:events';
import {stripTypeScriptTypes} from 'node:module';
const code=stripTypeScriptTypes(fs.readFileSync(UPSTREAM + '/packages/tui/src/stdin-buffer.ts','utf8')).replace(/^import .*;$/gm,'').replace(/^export /gm,'');
const StdinBuffer=new Function('EventEmitter','setTimeout','clearTimeout',code+';return StdinBuffer;')(EventEmitter,(_fn,ms)=>({ms}),()=>{});
const scenarios=JSON.parse(fs.readFileSync(0,'utf8'));
console.log(JSON.stringify(scenarios.map(steps=>{
 const buffer=new StdinBuffer();let events=[];
 buffer.on('data',x=>events.push(['data',x]));buffer.on('paste',x=>events.push(['paste',x]));
 return steps.map(([kind,text])=>{
  events=[];
  if(kind==='process')buffer.process(text);
  else if(kind==='flush')events=buffer.flush().map(x=>['data',x]);
  else buffer.clear();
  return {events,buffer:buffer.getBuffer(),timeout:buffer.timeout?.ms??null};
 });
})));
