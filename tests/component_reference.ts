import { UPSTREAM } from "./upstream_pin.mjs";
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const source=readFileSync(UPSTREAM + '/packages/tui/src/tui.ts','utf8');
assert.equal(createHash('sha256').update(source).digest('hex'),'2ca47c56f4a4f24b8c6a4c9c9f2a06004bfc312d9dbcd0ac1921a2cae32bc675');
const begin=source.indexOf('export function dispatchMouseEvent(');
const end=source.indexOf('export interface Component',begin);
const containerStart=source.indexOf('export class Container');
const containerEnd=source.indexOf('/**\n * TUI -',containerStart);
const compiled=new Bun.Transpiler({loader:'ts'}).transformSync((source.slice(begin,end)+source.slice(containerStart,containerEnd)).replaceAll('export ',''));
const {Container,retargetMouseEvent}=new Function(compiled+';return {Container,retargetMouseEvent};')();
const normalizeEvent=(e:any)=>Object.fromEntries(['type','button','wheelDelta','clickCount','x','y','screenX','screenY','width','height','shift','alt','ctrl'].map(k=>[k,e[k]??null]));
const normalizeResult=(r:any)=>r?{target:{...r.target,component:r.target.component.id},focusTarget:r.focusTarget?.id??null,capture:r.capture??false,focus:r.focus??false,render:r.render??null}:null;
function run(v:any){
 const calls:any[]=[];
 const components=v.children.map((s:any)=>({
  id:s.id,
  render(width:number){calls.push(['render',s.id,width]);return Array.from({length:s.height+(s.variable?width%3:0)},(_,i)=>`${s.id}:${i}`);},
  invalidate(){calls.push(['invalidate',s.id,null]);},
  handleInput(data:string){calls.push(['input',s.id,data]);},
  handleMouse(event:any){calls.push(['mouse',s.id,normalizeEvent(event)]);if(!s.response)return undefined;if(s.response.forward)return {...s.response,target:{...s.response.target,component:{id:s.response.target.component}},focusTarget:{id:s.response.focusTarget}};return s.response;}
 }));
 const c=new Container();c.id=999;
 const results:any[]=[null];
 for(const step of v.steps){
  let out:any=null;
  switch(step.op){
   case 'add': {const child=components.find((c:any)=>c.id===step.id);if(child)c.addChild(child);break;}
   case 'remove': c.removeChild(components.find((c:any)=>c.id===step.id));break;
   case 'clear': c.clear();break;
   case 'invalidate': c.invalidate();break;
   case 'render': out=c.render(step.width);break;
   case 'retarget': out=normalizeEvent(retargetMouseEvent(step.event,step.target));break;
   default:
    c.handleInput=step.delegates?()=>{}:undefined;
    out=normalizeResult(c.handleMouse(step.event));
  }
  results.push(out);
 }
 return {results,calls};
}
console.log(JSON.stringify(JSON.parse(process.argv[2]).map(run)));
