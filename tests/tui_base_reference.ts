import {readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2],{eastAsianWidth}=await import(resolve(process.argv[3]));
const transpiler=new Bun.Transpiler({loader:'ts'});
const hashes:Record<string,string>={
 'packages/tui/test/regression-overlay-cjk-boundary.test.ts':'51438c36784bb4ffb6304e1d179eb9daa046b8b93c80582c87c41f6415449b20',
 'packages/tui/src/tui.ts':'2ca47c56f4a4f24b8c6a4c9c9f2a06004bfc312d9dbcd0ac1921a2cae32bc675',
 'packages/tui/src/terminal-image.ts':'f29572354977fd4ef4cc76878d31cce3cb5c45cebdfc9b5c49b50ad9cfb3171f',
 'packages/tui/src/utils.ts':'8cda2d53e2361ac5aaf6d7345b2fee058c8df5743eae4e4e90c89a7072c026c3',
 'packages/tui/test/truncate-to-width.test.ts':'fd75a99d47ff465d56a1f3ede16e37ca7d29aa910e2322881e824e6c2937b7b8',
 'packages/tui/test/wrap-ansi.test.ts':'9c238d85ad676ca6d4e063caa8d44d493b0c220dd9aba9ea11a31d51c92d791d',
 'packages/tui/test/regression-regional-indicator-width.test.ts':'a057bc5b61cd287e2f2f554e878222ebace84a515e6cf67b87191eba5c91ae47',
 'packages/tui/test/tab-width.test.ts':'59fff93aeecb3809f41f7bf68d88ef8ba9f0f38cd3a2db785a1f16a0ac114419',
};
function pinned(file:string){const text=readFileSync(join(root,file),'utf8');assert.equal(createHash('sha256').update(text).digest('hex'),hashes[file],file);return text;}
const sourceText=pinned('packages/tui/src/utils.ts');
const compiled=transpiler.transformSync(sourceText.replace(/^import.*\n/, '')).replace(/\bexport /g,'');
const names=['visibleWidth','graphemeWidth','normalizeTerminalOutput','truncateToWidth','wrapTextWithAnsi','extractSegments','sliceWithWidth','sliceByColumn','cjkBreakRegex'];
const source=new Function('eastAsianWidth',compiled+';return {'+names.join(',')+'};')(eastAsianWidth);

const imageText=pinned('packages/tui/src/terminal-image.ts');
const imageCode=transpiler.transformSync(imageText.slice(imageText.indexOf('const KITTY_PREFIX'),imageText.indexOf('export function allocateImageId'))).replace(/\bexport /g,'');
const isImageLine=new Function(imageCode+';return isImageLine')();
const tuiText=pinned('packages/tui/src/tui.ts');
const tuiCode=transpiler.transformSync(tuiText.slice(tuiText.indexOf('const SEGMENT_RESET'),tuiText.indexOf('export type TuiMode'))).replace(/\bexport /g,'');
const composite=new Function('isImageLine','extractSegments','sliceWithWidth','visibleWidth','sliceByColumn',tuiCode+';return compositeTuiLine')(isImageLine,source.extractSegments,source.sliceWithWidth,source.visibleWidth,source.sliceByColumn);

const parseStart=tuiText.indexOf('function parseSizeValue(');
const parser=tuiText.slice(parseStart,tuiText.indexOf('/**',parseStart));
const layoutStart=tuiText.indexOf('\tprivate resolveOverlayLayout(');
const layoutMethods=tuiText.slice(layoutStart,tuiText.indexOf('\n\t/** Composite all overlays',layoutStart));
function method(start:string,next:string){const from=tuiText.indexOf(start);assert(from>=0,start);return tuiText.slice(from,tuiText.indexOf(next,from));}
const methods=layoutMethods+method('\tprotected compositeOverlays(','\n\tprotected applyLineResets(')+method('\tprotected dispatchMouseToOverlay(','\n\t/** Check if an overlay entry is currently visible')+method('\tprivate isOverlayVisible(','\n\t/** Find the visual-frontmost');
const dispatchSource=method('export function dispatchMouseEvent(','/** Recreate local coordinates');
const frameCode=transpiler.transformSync(parser+'\n'+dispatchSource+'\nclass Renderer {\n'+methods+'\ncompositeLineAt(...args:any[]){return compositeTuiLine(...args);}\n}').replace(/\bexport /g,'');
const Renderer=new Function('compositeTuiLine','visibleWidth','sliceByColumn',frameCode+';return Renderer;')(composite,source.visibleWidth,source.sliceByColumn);
function query(v:any){
 const state=new Renderer();state.terminal={columns:v.width,rows:v.height};const renders:any[]=[],calls:any[]=[];
 const components=new Map<number,any>();
 state.overlayStack=v.overlays.map((o:any)=>{
  const component={id:o.id,render(width:number){renders.push({id:o.id,width});return o.lines;},handleMouse(event:any){
   calls.push({id:o.id,x:event.x,y:event.y,screenX:event.screenX,screenY:event.screenY,width:event.width,height:event.height});
   if(o.mouse==='none')return undefined;
   if(o.mouse==='unhandled')return {handled:false};
   if(o.mouse==='nested'||o.mouse==='nested-no-focus')return {handled:true,target:{component:{id:o.id+1000},originX:event.screenX-event.x+1,originY:event.screenY-event.y+1,width:2,height:1},focusTarget:{id:o.id+1000},focus:o.mouse==='nested',capture:true,render:false};
   return {handled:o.mouse!=='focus'&&o.mouse!=='capture',focus:o.mouse==='focus',capture:o.mouse==='capture',render:false};
  }};components.set(o.id,component);
  return {component,hidden:!!o.hidden,focusOrder:o.order??o.id,options:{...o.options,visible:()=>o.visible!==false}};
 });
 const lines=state.compositeOverlays(v.base,v.width,v.height);
 const bounds=state.renderedOverlayLayouts.map((l:any)=>({id:l.entry.component.id,row:l.row,col:l.col,width:l.width,height:l.height}));
 if(v.removeLive)state.overlayStack=[];
 const mouse=(v.events??[]).map((event:any)=>{const result=state.dispatchMouseToOverlay({type:'press',button:'left',x:777,y:888,width:0,height:0,screenX:event.x,screenY:event.y});
  if(!result.result)return {hit:result.hit,result:null};
  const r=result.result;return {hit:result.hit,result:{target:{id:r.target.component.id,originX:r.target.originX,originY:r.target.originY,width:r.target.width,height:r.target.height},focusTarget:r.focusTarget?.id??null,capture:!!r.capture,focus:!!r.focus,render:r.render??null}};
 });
 return {lines,bounds,renders,mouse,calls};
}
console.log(JSON.stringify(JSON.parse(process.argv[4]).map(query)));
