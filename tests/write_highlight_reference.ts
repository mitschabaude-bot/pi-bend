// Test-only oracle: upstream writeRenderers.renderCall over streamed
// arguments, reusing the component (and its highlight cache) between steps.
// Arguments as for tests/write-highlight.bend; prints each call's text.
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {strict as assert} from 'node:assert';
const root='/home/agent/code/pi-mono';
const write=`${root}/packages/coding-agent/src/core/tools/renderers/write.ts`;
assert.equal(createHash('sha256').update(readFileSync(write)).digest('hex'),'84d715671a72c77821ab81aef79b39f5022082c78568683ab643d38ee735d07f');
const {initTheme,theme}=await import(`${root}/packages/coding-agent/src/modes/interactive/theme/theme.ts`);
const {writeRenderers}=await import(write);
initTheme('dark');
const [path,...rest]=process.argv.slice(2);
let component:any;
for(let i=0;i+1<rest.length;i+=2){
  const complete=rest[i]==='complete';
  component=writeRenderers.renderCall!({path,content:rest[i+1]},theme,{lastComponent:component,argsComplete:complete,expanded:true,isPartial:!complete,cwd:process.cwd()} as any);
  process.stdout.write(component.text+'\x1e\n');
}
