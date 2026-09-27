import { UPSTREAM } from './upstream_pin.mjs';
const { TuiAltScreen } = await import(UPSTREAM + '/packages/tui/src/tui-alt-screen.ts');
const tui = new TuiAltScreen({columns:80, rows:24, write() {}});
let render = false;
tui.requestRender = () => {render = true;};
const offset = value => String(value);
const log = event => `${event.type}:${event.button}:${event.x},${event.y}:${event.screenX},${event.screenY}:${event.width},${event.height}:${Number(event.shift)}${Number(event.alt)}${Number(event.ctrl)}:${event.clickCount ?? 0}:${event.wheelDelta ?? 0}`;
const component = {render: () => [], invalidate() {}, handleMouse(event) {
  console.log(log(event));
  if (event.type === 'release' || event.type === 'move') return undefined;
  return {handled:true, focus:event.type === 'press', capture:event.type === 'press'};
}};
Object.defineProperty(component, 'focused', {set(value) {console.log('focus:' + Number(value));}});
const box = (component, x,y,width,height,children=[]) => ({component, rect:{x,y,width,height}, clip:{x,y,width,height}, children, layer:0});
component.id = 1;
const parent = {id:2,render:()=>[],invalidate(){}};
const root = {id:3,render:()=>[],invalidate(){}};
const overlay = box({id:4,render:()=>[],invalidate(){}},10,5,20,4); overlay.layer=1;
const leaf = box(component,10,5,20,4);
tui.currentLayout = {root:box(root,0,0,80,24,[box(parent,8,3,30,10,[leaf]),overlay]),width:80,height:24,lines:[]};
const {getLayoutBoxesAt} = await import(UPSTREAM + '/packages/tui/src/layout.ts');
for (const [x,y] of [[12,6],[35,6],[79,23],[80,23]]) console.log('hits:' + getLayoutBoxesAt(tui.currentLayout,x,y).map(b=>b.component.id).join(','));
let input=''; for await (const chunk of process.stdin) input+=chunk;
for (const data of JSON.parse(input)) {
  render=false;
  tui.handleViewportInput(data);
  console.log('render:' + Number(render));
}
process.exit(0);
