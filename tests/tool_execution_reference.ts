import { UPSTREAM } from "./upstream_pin.mjs";
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {strict as assert} from 'node:assert';
const { KeybindingsManager, setKeybindings } = await import(UPSTREAM + '/packages/tui/src/keybindings.ts');
const { KEYBINDINGS } = await import(UPSTREAM + '/packages/coding-agent/src/core/keybindings.ts');
const { ToolExecutionComponent } = await import(UPSTREAM + '/packages/coding-agent/src/modes/interactive/components/tool-execution.ts');
const { initTheme } = await import(UPSTREAM + '/packages/coding-agent/src/modes/interactive/theme/theme.ts');
const { Text } = await import(UPSTREAM + '/packages/tui/src/components/text.ts');
const { readRenderers } = await import(UPSTREAM + '/packages/coding-agent/src/core/tools/renderers/read.ts');
const { createShellRenderers } = await import(UPSTREAM + '/packages/coding-agent/src/core/tools/renderers/bash.ts');
const { editRenderers } = await import(UPSTREAM + '/packages/coding-agent/src/core/tools/renderers/edit.ts');
const { writeRenderers } = await import(UPSTREAM + '/packages/coding-agent/src/core/tools/renderers/write.ts');
for (const [file,digest] of [
 ['packages/coding-agent/src/modes/interactive/components/tool-execution.ts','1463e89622b305847fd129ea81a5f8d969778a650daf5357bd3771c79aef349f'],
 ['packages/coding-agent/src/core/tools/render-utils.ts','38913e15575b7c314687c1a7d53b2763eecb8e7a86b0b58d7b5532c900503cf3'],
 ['packages/coding-agent/src/modes/interactive/theme/dark.json','103a5aecb74a2dab5cc903c9741845ee6158658ce2ff6e5445948784116eaef8'],
 ['packages/coding-agent/src/modes/interactive/components/keybinding-hints.ts','76b13ee8bfc6e49d5b2b5496eac13523bd9aad95770cbfa4a239336131f94aae'],
 ['packages/coding-agent/src/core/keybindings.ts','38e8b20700e40452acab4c9583d96d9c304bbe15c471e214e50b65ec3b3f1945'],
 ['packages/tui/src/keybindings.ts','eea5e3fe258ad50337595bb5320955a6d97bac0c8f6c0a838f988d75079bcf38'],
 ['packages/tui/src/components/box.ts','f79d30c9c263064df656dc55674b5d951bf765ffbbf658f400f449c44f6dab98'],
 ['packages/tui/src/components/text.ts','3042e09dd8dcb870c23506e6fafb2dfcc095e7e375adad2fb62e447da17e5e3b'],
 ['packages/coding-agent/src/core/tools/renderers/read.ts','93699c267fc824c0016ac182b68c01c45feeb621c64fc44a814a96e3c951f106'],
 ['packages/coding-agent/src/core/tools/renderers/bash.ts','f04ab261d9f915f7b43a97ac679fb38d5646110855a886474593dc5d973f6764'],
 ['packages/coding-agent/src/core/tools/renderers/edit.ts','0c1bafcf74ad2b703bf5ab193e72084a1da80231a77abddefc23c5bb20558731'],
 ['packages/coding-agent/src/core/tools/renderers/write.ts','84d715671a72c77821ab81aef79b39f5022082c78568683ab643d38ee735d07f'],
] as const) assert.equal(createHash('sha256').update(readFileSync(UPSTREAM + '/'+file)).digest('hex'),digest);
initTheme('dark');
setKeybindings(new KeybindingsManager(KEYBINDINGS));
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

const builtins:any={read:readRenderers,bash:createShellRenderers('$'),edit:{...editRenderers,renderShell:'self'},write:writeRenderers};
for (const [name,args] of Object.entries({read:{path:'notes.txt'},bash:{command:'printf hello'},edit:{path:'notes.txt'},write:{path:'notes.txt',content:'one\ntwo'}})) {
 const component=new ToolExecutionComponent(name,name,args,{},builtins[name],ui,process.cwd());
 out(name+'-pending',component);
 component.updateResult({content:[{type:'text',text:'one\ntwo\nthree'}],isError:false},true);out(name+'-partial',component);
 component.updateResult({content:[{type:'text',text:'one\ntwo\nthree'}],isError:false},false);out(name+'-final',component);
 component.updateResult({content:[{type:'text',text:'bad input'}],isError:true},false);out(name+'-error',component);
}
const range=new ToolExecutionComponent('read','range',{path:'notes.txt',offset:4,limit:2},{},readRenderers,ui,process.cwd());
out('read-range',range,80);range.updateResult({content:[{type:'text',text:'one\ntwo'}],isError:false},false);range.setExpanded(true);out('read-expanded',range,80);
const longBash=new ToolExecutionComponent('bash','long',{command:'seq 7'},{},builtins.bash,ui,process.cwd());
longBash.updateResult({content:[{type:'text',text:Array.from({length:7},(_,i)=>`line-${i+1}`).join('\n')}],isError:false},false);out('bash-preview',longBash,80);
const longWrite=new ToolExecutionComponent('write','long',{path:'notes.txt',content:Array.from({length:12},(_,i)=>`line-${i+1}`).join('\n')},{},writeRenderers,ui,process.cwd());
out('write-preview',longWrite,80);longWrite.setExpanded(true);out('write-expanded',longWrite,80);
