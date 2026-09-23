import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {strict as assert} from 'node:assert';
import {ToolExecutionComponent} from '/home/agent/code/pi-mono/packages/coding-agent/src/modes/interactive/components/tool-execution.ts';
import {initTheme} from '/home/agent/code/pi-mono/packages/coding-agent/src/modes/interactive/theme/theme.ts';
import {Text} from '/home/agent/code/pi-mono/packages/tui/src/components/text.ts';
for (const [file,digest] of [
 ['packages/coding-agent/src/modes/interactive/components/tool-execution.ts','1463e89622b305847fd129ea81a5f8d969778a650daf5357bd3771c79aef349f'],
 ['packages/coding-agent/src/core/tools/render-utils.ts','38913e15575b7c314687c1a7d53b2763eecb8e7a86b0b58d7b5532c900503cf3'],
 ['packages/coding-agent/src/modes/interactive/theme/dark.json','103a5aecb74a2dab5cc903c9741845ee6158658ce2ff6e5445948784116eaef8'],
 ['packages/coding-agent/src/modes/interactive/components/keybinding-hints.ts','76b13ee8bfc6e49d5b2b5496eac13523bd9aad95770cbfa4a239336131f94aae'],
 ['packages/tui/src/components/box.ts','f79d30c9c263064df656dc55674b5d951bf765ffbbf658f400f449c44f6dab98'],
 ['packages/tui/src/components/text.ts','3042e09dd8dcb870c23506e6fafb2dfcc095e7e375adad2fb62e447da17e5e3b'],
] as const) assert.equal(createHash('sha256').update(readFileSync('/home/agent/code/pi-mono/'+file)).digest('hex'),digest);
initTheme('dark');
const ui:any={requestRender(){}};
const out=(label:string,component:ToolExecutionComponent,width=28)=>process.stdout.write(label+'\x1e'+component.render(width).join('\x1f')+'\n');
const generic=new ToolExecutionComponent('custom_tool','g1',{path:'notes.txt'}, {}, undefined, ui, process.cwd());
out('generic-pending',generic);
generic.updateArgs({path:'notes.txt',limit:2});out('generic-args',generic);
generic.markExecutionStarted();generic.setArgsComplete();out('generic-started',generic);
generic.updateResult({content:[{type:'text',text:'first\nsecond'}],isError:false},true);out('generic-partial',generic);
generic.updateResult({content:[{type:'text',text:'first\nsecond'}],isError:false},false);out('generic-success',generic);
generic.updateResult({content:[{type:'text',text:'bad\r\n\x1b[31mred\x1b[0m'}],isError:true},false);out('generic-error',generic);
const defined:any={};
const fallback=new ToolExecutionComponent('custom_tool','f1',{foo:'bar'}, {}, defined, ui, process.cwd());
out('fallback-pending',fallback);
fallback.updateResult({content:[{type:'text',text:Array.from({length:12},(_,i)=>`line-${i+1}`).join('\n')}],isError:false},false);out('fallback-preview',fallback);
fallback.setExpanded(true);out('fallback-expanded',fallback);
fallback.updateResult({content:[{type:'text',text:'failed'}],isError:true},false);out('fallback-error',fallback);
const rendered=new ToolExecutionComponent('custom_tool','r1',{}, {}, {renderCall:()=>new Text('custom call',0,0),renderResult:()=>new Text('custom result',0,0)}, ui, process.cwd());
out('rendered-call',rendered);rendered.updateResult({content:[{type:'text',text:'done'}],isError:false},false);out('rendered-result',rendered);
const self=new ToolExecutionComponent('custom_tool','s1',{}, {}, {renderShell:'self',renderCall:()=>new Text('own call',0,0),renderResult:()=>new Text('own result',0,0)},ui,process.cwd());
out('self-call',self);self.updateResult({content:[{type:'text',text:'done'}],isError:false},false);out('self-result',self);
const emptyBox=new ToolExecutionComponent('custom_tool','e1',{}, {}, {renderCall:()=>new Text('',0,0),renderResult:()=>new Text('',0,0)},ui,process.cwd());
out('boxed-empty',emptyBox);
const emptySelf=new ToolExecutionComponent('custom_tool','e2',{}, {}, {renderShell:'self',renderCall:()=>new Text('',0,0),renderResult:()=>new Text('',0,0)},ui,process.cwd());
out('self-empty',emptySelf);emptySelf.updateResult({content:[],isError:false},false);out('self-empty-result',emptySelf);
const adapter=new ToolExecutionComponent('custom_tool','a1',{}, {}, undefined,ui,process.cwd());
adapter.updateResult({content:[{type:'text',text:'from agent'}],isError:false},false);out('agent-adapter',adapter);
