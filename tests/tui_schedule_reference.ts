import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
const root=process.argv[2];
const source=readFileSync(join(root,'packages/tui/src/tui.ts'),'utf8');
assert.equal(createHash('sha256').update(source).digest('hex'),'2ca47c56f4a4f24b8c6a4c9c9f2a06004bfc312d9dbcd0ac1921a2cae32bc675');
function method(start:string,next:string){const from=source.indexOf(start);assert(from>=0,start);const end=source.indexOf(next,from);assert(end>=0,next);return source.slice(from,end);}
const methods=(method('\tstart(): void {','\n\taddInputListener(')+method('\tstop(options: TuiStopOptions = {}): void {','\n\trenderNow(')+method('\trenderNow(force = false): void {','\n\trequestRender(')+method('\trequestRender(force = false): void {','\n\tprivate requestImmediateRender(')+method('\tprivate requestImmediateRender(): void {','\n\tprivate cancelRenderTimer(')+method('\tprivate cancelRenderTimer(): void {','\n\tprivate scheduleRender(')+method('\tprivate scheduleRender(): void {','\n\tprivate handleTerminalInput(')).replace('TuiBase.MIN_RENDER_INTERVAL_MS','Renderer.MIN_RENDER_INTERVAL_MS');
const code=new Bun.Transpiler({loader:'ts'}).transformSync(`class Renderer {
  renderRequested=false; immediateRenderScheduled=false; renderTimer:any=undefined; lastRenderAt=0; stopped=false;
  static readonly MIN_RENDER_INTERVAL_MS=16;
  terminal:any; terminalColorSchemeNotificationsEnabled=false;
  resetRenderState(){ log('x'); } doRender(){ log('d'); }
  beforeTerminalStart(){} afterTerminalStart(){} beforeTerminalStop(){} afterTerminalStop(){} queryCellSize(){}
  ${methods}
}`);
function run(actions:string){
 let now=0,nextTimer=1;let ticks:Function[]=[],timers=new Map<number,Function>();let effects:string[]=[];
 const log=(s:string)=>effects.push(s);
 const fakeProcess={nextTick:(callback:Function)=>{ticks.push(callback);log('pending');}};
 const setTimeout=(callback:Function,delay:number)=>{const id=nextTimer++;timers.set(id,callback);log(`t${id}/${delay}`);return id;};
 const clearTimeout=(id:number)=>{timers.delete(id);log(`c${id}`);};
 const performance={now:()=>now};
 const Renderer=new Function('process','setTimeout','clearTimeout','performance','log',code+';return Renderer')(fakeProcess,setTimeout,clearTimeout,performance,log);
 const state=new Renderer();state.terminal={start(){},stop(){},hideCursor(){},showCursor(){},write(){}};
 const lines:string[]=[];
 for(const action of actions){
  effects=[];
  if(action==='r')state.requestRender();
  if(action==='f')state.requestRender(true);
  if(action==='i')state.requestImmediateRender();
  if(action==='q')ticks.shift()?.();
  if(action==='t'){const id=state.renderTimer;if(id!==undefined){const callback=timers.get(id);timers.delete(id);callback?.();}}
  if(action==='n')state.renderNow();
  if(action==='N')state.renderNow(true);
  if(action==='x')state.stop();
  if(action==='b')state.start();
  // The queue kind is determined by the source method that enqueued it.
  const queued=effects.map(e=>e==='pending'?(state.immediateRenderScheduled?'i':'s'):e);
  lines.push(`${+state.renderRequested}${+state.immediateRenderScheduled}:${state.renderTimer??'-'}:${nextTimer}:${state.lastRenderAt}:${+state.stopped}|${queued.join(',')}${queued.length?',':''}`);
  now+=5;
 }
 return lines;
}
console.log(JSON.stringify(run(process.argv[3]??'')));
