import { UPSTREAM } from './upstream_pin.mjs';
process.env.COLORTERM='truecolor'; process.env.FORCE_COLOR='3';
const {initTheme}=await import(UPSTREAM+'/packages/coding-agent/src/modes/interactive/theme/theme.ts');
const {OAuthSelectorComponent}=await import(UPSTREAM+'/packages/coding-agent/src/modes/interactive/components/oauth-selector.ts');
const {KEYBINDINGS}=await import(UPSTREAM+'/packages/coding-agent/src/core/keybindings.ts');
const {KeybindingsManager,setKeybindings}=await import(UPSTREAM+'/packages/tui/src/keybindings.ts');
setKeybindings(new KeybindingsManager(KEYBINDINGS)); initTheme('dark');
const providers=[
 {id:'anthropic',name:'Anthropic',authType:'oauth',method:{name:'Claude account'},status:{type:'oauth',source:'OAuth'}},
 {id:'anthropic',name:'Anthropic',authType:'api_key',method:{name:'Anthropic API key'},status:{type:'oauth',source:'OAuth'}},
 {id:'openai',name:'OpenAI',authType:'api_key',method:{name:'OpenAI API key'},status:{type:'api_key',source:'OPENAI_API_KEY'}},
 {id:'local-proxy',name:'local-proxy',authType:'api_key',method:{name:'Proxy token'},status:{type:'api_key',source:'key in models.json'}},
 {id:'command-proxy',name:'command-proxy',authType:'api_key',method:{name:'Shell credential'},status:{type:'api_key',source:'command in models.json'}},
 {id:'google',name:'Google',authType:'api_key',method:{name:'Google Cloud credentials'}},
 {id:'long',name:'A very long provider name that should be truncated',authType:'oauth',method:{name:'Long account'}},
 {id:'中',name:'日本語',authType:'oauth',method:{name:'Account'},status:{type:'api_key',source:'stored credential'}},
 {id:'nine',name:'Nine',authType:'api_key',method:{name:'Token'},status:{type:'api_key',source:'stored credential'}},
 {id:'ten',name:'Ten',authType:'oauth',method:{name:'Account'}}
];
const keys={up:'\x1b[A',down:'\x1b[B',enter:'\r',escape:'\x1b',left:'\x1b[D',right:'\x1b[C',home:'\x01',end:'\x05',backspace:'\x7f',delete:'\x1b[3~',wordLeft:'\x1bb',wordRight:'\x1bf',killWord:'\x17',yank:'\x19',undo:'\x1f',save:'\x13',tab:'\t'};
let input='';for await(const chunk of process.stdin)input+=chunk;
const results=JSON.parse(input).map(c=>{
 const component=new OAuthSelectorComponent(c.mode,c.empty?[]:providers,()=>{},()=>{},c.query);
 component.focused=true;
 // Compare native scalar cursor positions; rendered graphemes remain exact.
 const snapshot=response=>({selected:component.filteredProviders[component.selectedIndex]?component.filteredProviders[component.selectedIndex].id+'/'+component.filteredProviders[component.selectedIndex].authType:null,query:component.searchInput.getValue(),cursor:Array.from(component.searchInput.getValue().slice(0,component.searchInput.cursor)).length,response:response?{handled:response.handled??false,capture:response.capture??false,focus:response.focus??false,render:response.render??null}:null,lines:component.render(c.width)});
 const out=[snapshot(null)];
 for(const step of c.steps){
  let response;
  if(typeof step==='string')component.handleInput(keys[step]??step);
  else if ('focus' in step)component.focused=step.focus;
  else{
   let base=0;for(const child of component.mouseLayout.children){if(child.component===component.searchInput)break;base+=child.height;}
   const y=step.zone==='search'?base:base+2;
   response=component.handleMouse({type:'press',button:'left',x:step.x,y,screenX:step.x,screenY:y,width:c.width,height:1000,shift:false,alt:false,ctrl:false});
  }
  out.push(snapshot(response));
 }
 return out;
});
await new Promise(resolve=>process.stdout.write(JSON.stringify(results),resolve));process.exit(0);
