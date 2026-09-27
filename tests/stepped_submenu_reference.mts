import { UPSTREAM } from './upstream_pin.mjs';
process.env.COLORTERM='truecolor'; process.env.FORCE_COLOR='3';
const {initTheme}=await import(UPSTREAM+'/packages/coding-agent/src/modes/interactive/theme/theme.ts');
const {SteppedSubmenu}=await import(UPSTREAM+'/packages/coding-agent/src/modes/interactive/components/settings-submenu.ts');
const {KEYBINDINGS}=await import(UPSTREAM+'/packages/coding-agent/src/core/keybindings.ts');
const {KeybindingsManager,setKeybindings}=await import(UPSTREAM+'/packages/tui/src/keybindings.ts');
setKeybindings(new KeybindingsManager(KEYBINDINGS)); initTheme('dark');
const keys={up:'\x1b[A',down:'\x1b[B',enter:'\r',escape:'\x1b',left:'\x1b[D',right:'\x1b[C',home:'\x01',end:'\x05',backspace:'\x7f',delete:'\x1b[3~',wordLeft:'\x1bb',wordRight:'\x1bf',killWord:'\x17',yank:'\x19',undo:'\x1f',save:'\x13',tab:'\t'};
let input='';for await(const chunk of process.stdin)input+=chunk;
const results=JSON.parse(input).map(c=>{
 const events=[];let count=0;
 const component=new SteppedSubmenu([
  {key:'model',title:'Choose model',description:'Select model',options:()=>[{value:'a',label:'Alpha',description:'saved '+count},{value:'b',label:'Beta'},{value:'c',label:'Charlie'}],preselect:()=> 'b',searchable:true},
  {key:'level',title:ctx=>'Level for '+(ctx.model??'?'),description:'Select level',options:ctx=>ctx.model==='c'?[]:[{value:'low',label:'Low',description:'Quick'},{value:'high',label:'High',description:'Careful'}],preselect:()=> 'high'}
 ],ctx=>{events.push('complete:'+Object.entries(ctx).map(([k,v])=>k+'='+v).join(';'));count++;},()=>events.push('cancel'),{loop:c.loop,startAtStep:c.start,initialContext:c.start?{model:'a'}:{}});
 const snapshot=()=>({context:Object.entries(component.context).map(([k,v])=>k+'='+v).join(';'),index:component.activeComponent.searchInput?0:1,selected:component.activeComponent.selectList.getSelectedItem()?.value??null,query:component.activeComponent.searchInput?.getValue()??'',events:[...events],lines:component.render(c.width)});
 const out=[snapshot()];
 for(const step of c.steps){component.handleInput(keys[step]??step);out.push(snapshot());}
 return out;
});
await new Promise(resolve=>process.stdout.write(JSON.stringify(results),resolve));process.exit(0);
