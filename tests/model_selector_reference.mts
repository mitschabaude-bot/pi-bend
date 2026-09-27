import { UPSTREAM } from './upstream_pin.mjs';
process.env.COLORTERM='truecolor'; process.env.FORCE_COLOR='3';
const {initTheme}=await import(UPSTREAM+'/packages/coding-agent/src/modes/interactive/theme/theme.ts');
const {ModelSelectorComponent}=await import(UPSTREAM+'/packages/coding-agent/src/modes/interactive/components/model-selector.ts');
const {KEYBINDINGS}=await import(UPSTREAM+'/packages/coding-agent/src/core/keybindings.ts');
const {KeybindingsManager,setKeybindings}=await import(UPSTREAM+'/packages/tui/src/keybindings.ts');
setKeybindings(new KeybindingsManager(KEYBINDINGS)); initTheme('dark');
const specs=[['zeta','last'],['alpha','a-long-model-name-with-dashes'],['alpha','other'],['éclair','accent'],['alpha_beta','under'],['alpha-beta','dash'],['中','模型'],['alpha','mini'],['alpha','max'],['alpha','extra'],['alpha','eleven'],['alpha','twelve']];
const models=specs.map(([provider,id])=>({provider,id,name:'Display '+id}));
const keys={up:'\x1b[A',down:'\x1b[B',enter:'\r',escape:'\x1b',left:'\x1b[D',right:'\x1b[C',home:'\x01',end:'\x05',backspace:'\x7f',delete:'\x1b[3~',wordLeft:'\x1bb',wordRight:'\x1bf',killWord:'\x17',yank:'\x19',undo:'\x1f',save:'\x13',tab:'\t'};
let input='';for await(const chunk of process.stdin)input+=chunk;
const results=JSON.parse(input).map(c=>{
 const available=c.empty?[]:models;
 const runtime={getAvailableSnapshot:()=>available,getModel:(provider,id)=>available.find(m=>m.provider===provider&&m.id===id),getError:()=>undefined,refresh:()=>new Promise(()=>{})};
 let action='continue';
 const component=new ModelSelectorComponent({requestRender(){}},models[c.current],runtime,c.scoped.map(i=>({model:models[i]})),m=>{action='chosen:'+m.provider+'/'+m.id;},()=>{action='cancel';},c.query,m=>{action='default:'+m.provider+'/'+m.id;},models[c.default]);
 component.focused=true;
 // Compare native scalar cursor positions; rendered graphemes remain exact.
 const snapshot=response=>({selected:component.filteredModels[component.selectedIndex]?component.filteredModels[component.selectedIndex].model.provider+'/'+component.filteredModels[component.selectedIndex].model.id:null,query:component.searchInput.getValue(),cursor:Array.from(component.searchInput.getValue().slice(0,component.searchInput.cursor)).length,response:response?{handled:response.handled??false,capture:response.capture??false,focus:response.focus??false,render:response.render??null}:null,action,lines:component.render(c.width)});
 const out=[snapshot(null)];
 for(const step of c.steps){
  action='continue';let response;
  if(typeof step==='string')component.handleInput(keys[step]??step);
  else{
   let base=0;for(const child of component.mouseLayout.children){if(child.component===component.searchInput)break;base+=child.height;}
   const y=step.zone==='search'?base:base+2;
   response=component.handleMouse({type:'press',button:'left',x:step.x,y,screenX:step.x,screenY:y,width:c.width,height:1000,shift:false,alt:false,ctrl:false});
  }
  out.push(snapshot(response));
 }
 component.dispose();return out;
});
await new Promise(resolve=>process.stdout.write(JSON.stringify(results),resolve));process.exit(0);
