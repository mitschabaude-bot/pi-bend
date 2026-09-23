import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
const source=readFileSync(join(process.argv[2],'packages/tui/src/tui.ts'),'utf8');
assert.equal(createHash('sha256').update(source).digest('hex'),'2ca47c56f4a4f24b8c6a4c9c9f2a06004bfc312d9dbcd0ac1921a2cae32bc675');
const keysText=readFileSync(join(process.argv[2],'packages/tui/src/keys.ts'),'utf8');
assert.equal(createHash('sha256').update(keysText).digest('hex'),'b972facce4233a4623239fc38029e28cae15d0fb326558c0c09dc02cf4345fa7');
const {isKeyRelease}=await import(join(process.argv[2],'packages/tui/src/keys.ts'));
function method(start:string,next:string){const from=source.indexOf(start);assert(from>=0,start);const end=source.indexOf(next,from);assert(end>=0,next);return source.slice(from,end);}
const methods=method('\tprotected compositeOverlays(','\n\tprotected applyLineResets(')+method('\tprivate isOverlayVisible(','\n\t/** Find the visual-frontmost')+method('\tprivate getTopmostVisibleOverlay(','\n\toverride invalidate(')+method('\tprivate setFocusInternal(','\n\tprivate clearOverlayFocusRestore(')+method('\tprivate getVisibleOverlayFocusRestore(','\n\tprivate isOverlayFocusAncestor(')+method('\tprivate handleTerminalInput(','\n\tprivate consumeOsc11BackgroundResponse(');
const guard=method('export function isFocusable(','\n/**').replace('export ','');
const code=new Bun.Transpiler({loader:'ts'}).transformSync(`${guard}\nclass Renderer {
  overlayStack:any[]=[]; renderedOverlayLayouts:any[]=[]; focusedComponent:any=null; inputListeners=new Set(); terminal:any={columns:8,rows:3}; onDebug:any; overlayFocusRestore:any={status:'inactive'};
  resolveOverlayLayout(){return {width:2,maxHeight:undefined,row:0,col:0};}
  compositeLineAt(base:string){return base;}
  consumeOsc11BackgroundResponse(){return false;} consumeTerminalColorSchemeReport(){return false;} consumeCellSizeResponse(){return false;}
  setFocus(component:any){this.setFocusInternal({component,overlayFocusRestore:'clear'});} clearOverlayFocusRestore(){this.overlayFocusRestore={status:'inactive'};}
  isOverlayFocusAncestor(){return false;} isComponentMounted(){return true;} resolveBlockedOverlayFocusResume(){return null;}
  requestImmediateRender(){calls.push('Q');}
  ${methods}
}`);
const calls:string[]=[];let visible=true;
const Renderer=new Function('matchesKey','isKeyRelease','visibleWidth','sliceByColumn','calls',code+';return Renderer')(()=>false,isKeyRelease,(s:string)=>s.length,(s:string)=>s,calls);
const base={focused:false,handleInput(){calls.push('I1')}};
const overlay={focused:true,render(){return ['OV']},handleInput(){calls.push('I3')}};
for(const [component,id] of [[base,1],[overlay,3]] as const){let state=component.focused;Object.defineProperty(component,'focused',{get(){return state},set(value:boolean){state=value;calls.push(`F${id}${value?'+':'-'}`)}});}
const renderer=new Renderer();const entry={component:overlay,preFocus:base,hidden:false,focusOrder:1,options:{width:2,visible:(width:number,height:number)=>{calls.push(`V3/${width}x${height}`);return visible;}}};
renderer.overlayStack=[entry];renderer.focusedComponent=overlay;
renderer.compositeOverlays(['A'],8,3);const renderVisible=[...calls];calls.length=0;
renderer.handleTerminalInput('\x1b[97;1:3u');const releaseVisible=[...calls];calls.length=0;
renderer.handleTerminalInput('a');const inputVisible=[...calls];calls.length=0;
visible=false;renderer.compositeOverlays(['A'],8,3);const renderHidden=[...calls];calls.length=0;
renderer.handleTerminalInput('b');const inputHidden=[...calls];
console.log(JSON.stringify({renderVisible,releaseVisible,inputVisible,renderHidden,inputHidden,focused:renderer.focusedComponent===base?'base':'overlay'}));
