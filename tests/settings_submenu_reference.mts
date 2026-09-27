import { UPSTREAM } from './upstream_pin.mjs';
process.env.COLORTERM='truecolor'; process.env.FORCE_COLOR='3';
const {initTheme}=await import(UPSTREAM+'/packages/coding-agent/src/modes/interactive/theme/theme.ts');
const {SelectSubmenu}=await import(UPSTREAM+'/packages/coding-agent/src/modes/interactive/components/settings-submenu.ts');
const {KEYBINDINGS}=await import(UPSTREAM+'/packages/coding-agent/src/core/keybindings.ts');
const {KeybindingsManager,setKeybindings}=await import(UPSTREAM+'/packages/tui/src/keybindings.ts');
setKeybindings(new KeybindingsManager(KEYBINDINGS)); initTheme('dark');
const items=[{value:'a',label:'A long model name [provider]',description:'high'}, {value:'b',label:'Beta'}, {value:'c',label:'Charlie',description:'a long description that will be clipped'}, ...['Delta','Echo','Foxtrot','Golf','Hotel','India','Juliet','Kilo','Lima'].map((label,i)=>({value:String.fromCharCode(100+i),label}))];
const keys={up:'\x1b[A',down:'\x1b[B',enter:'\r',escape:'\x1b',left:'\x1b[D',right:'\x1b[C',home:'\x01',end:'\x05',backspace:'\x7f',delete:'\x1b[3~',wordLeft:'\x1bb',wordRight:'\x1bf',killWord:'\x17',yank:'\x19',undo:'\x1f',save:'\x13',tab:'\t'};
let input='';for await(const chunk of process.stdin)input+=chunk;
const results=JSON.parse(input).map(c=>{
 let action='continue';
 const component=new SelectSubmenu('Select a setting',c.description,c.empty?[]:items,c.current,value=>{action='selected:'+value;},()=>{action='cancel';},value=>{action='selection:'+value;},{searchable:c.searchable});
 // Compare native scalar cursor positions; rendered graphemes remain exact.
 const snapshot=()=>({selected:component.selectList.getSelectedItem()?.value??null,query:component.searchInput?.getValue()??'',cursor:component.searchInput?Array.from(component.searchInput.getValue().slice(0,component.searchInput.cursor)).length:0,action,lines:component.render(c.width)});
 const out=[snapshot(null)];
 for(const step of c.steps){
  action='continue';let response;
  component.handleInput(keys[step]??step);
  out.push(snapshot(response));
 }
 return out;
});
await new Promise(resolve=>process.stdout.write(JSON.stringify(results),resolve));process.exit(0);
