import { UPSTREAM } from "./upstream_pin.mjs";
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const source=readFileSync(UPSTREAM + '/packages/tui/src/tui.ts','utf8');
assert.equal(createHash('sha256').update(source).digest('hex'),'2ca47c56f4a4f24b8c6a4c9c9f2a06004bfc312d9dbcd0ac1921a2cae32bc675');
function slice(a:string,b:string){const start=source.indexOf(a);assert(start>=0);const end=source.indexOf(b,start);assert(end>start);return source.slice(start,end);}
const methods=slice('\tgetFocusedComponent():','\t/** Check if there are any visible overlays */')+slice('\tprivate isOverlayVisible(','\toverride invalidate():');
const prepare=slice('\t\t// If focused component is an overlay,','\t\t// Pass input to focused component');
const compiled=new Bun.Transpiler({loader:'ts'}).transformSync(`class Container {children=[];} function isFocusable(c){return c!==null;} class Policy extends Container {${methods} prepareInput(){${prepare}}} `);
const Policy=new Function(compiled+';return Policy;')();
function run(steps:any[]){
 const p=new Policy(),components=new Map(),handles=new Map();let next=1,calls:any[]=[],hide=false,render=false;
 p.focusedComponent=null;p.overlayStack=[];p.overlayFocusRestore={status:'inactive'};p.focusOrderCounter=0;
 p.terminal={columns:80,rows:24,hideCursor(){hide=true;}};p.requestRender=()=>{render=true;};
 const component=(id:number|null)=>id==null?null:components.get(id)??(()=>{const c={id,set focused(v:boolean){calls.push([id,v]);}};components.set(id,c);return c;})();
 const output=[];
 for(const s of steps){
  calls=[];hide=false;render=false;
  if(s.mounted)p.children=s.mounted.map(component);
  switch(s.op){
   case 'show':{const slot={visible:s.visible??true};const h=p.showOverlay(component(s.component),{nonCapturing:s.passive??false,visible:()=>slot.visible});const entry=p.overlayStack.at(-1);entry.handle=next;handles.set(next++,{h,slot,entry});break;}
   case 'focus':p.setFocus(component(s.target));break;
   case 'hide':handles.get(s.handle)?.h.hide();break;
   case 'pop':p.hideOverlay();break;
   case 'hidden':handles.get(s.handle)?.h.setHidden(s.value);break;
   case 'visible':{const h=handles.get(s.handle);if(h)h.slot.visible=s.value;break;}
   case 'focusOverlay':handles.get(s.handle)?.h.focus();break;
   case 'unfocus':handles.get(s.handle)?.h.unfocus(Object.hasOwn(s,'target')?{target:component(s.target)}:undefined);break;
   case 'input':p.prepareInput();break;
  }
  const r=p.overlayFocusRestore;
  output.push({focus:p.focusedComponent?.id??null,entries:p.overlayStack.map((e:any)=>({handle:e.handle,component:e.component.id,previous:e.preFocus?.id??null,hidden:e.hidden,visible:e.options.visible(),passive:e.options.nonCapturing,order:e.focusOrder})),restore:r.status==='inactive'?{status:r.status}:r.status==='eligible'?{status:r.status,overlay:r.overlay.handle}:{status:r.status,overlay:r.overlay.handle,blockedBy:r.blockedBy.id,resume:r.resume.status,target:r.resume.target?.id??null},order:p.focusOrderCounter,calls,hide,render});
 }
 return output;
}
console.log(JSON.stringify(JSON.parse(process.argv[2]).map(run)));
