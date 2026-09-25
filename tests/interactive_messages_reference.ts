import { UPSTREAM } from "./upstream_pin.mjs";
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { strict as assert } from 'node:assert';
const { UserMessageComponent } = await import(UPSTREAM + '/packages/coding-agent/src/modes/interactive/components/user-message.ts');
const { AssistantMessageComponent } = await import(UPSTREAM + '/packages/coding-agent/src/modes/interactive/components/assistant-message.ts');
const { initTheme } = await import(UPSTREAM + '/packages/coding-agent/src/modes/interactive/theme/theme.ts');
const source=UPSTREAM + '/packages/coding-agent/src/modes/interactive/';
for (const [file,digest] of [
 ['components/user-message.ts','234d4f2544a0cb60082a6012a63576cdda4e9f99cdd0560129dd1efe5c6c7b1d'],
 ['components/assistant-message.ts','f8a20228291816aec253d3f115fec5ba765807275bc14077780225117e5912cb'],
 ['theme/dark.json','103a5aecb74a2dab5cc903c9741845ee6158658ce2ff6e5445948784116eaef8'],
] as const) assert.equal(createHash('sha256').update(readFileSync(source+file)).digest('hex'),digest);
for (const [file,digest] of [
 ['markdown.ts','704c1c714a7ff6bdec55573ab38393726fa73a7b47cf4c1161ccc4f08530ac28'],
 ['box.ts','f79d30c9c263064df656dc55674b5d951bf765ffbbf658f400f449c44f6dab98'],
 ['text.ts','3042e09dd8dcb870c23506e6fafb2dfcc095e7e375adad2fb62e447da17e5e3b'],
] as const) assert.equal(createHash('sha256').update(readFileSync(UPSTREAM + '/packages/tui/src/components/'+file)).digest('hex'),digest);
initTheme('dark');
const out=(label:string,lines:string[])=>process.stdout.write(label+'\x1e'+lines.join('\x1f')+'\n');
const message=(content:any[],stopReason='stop',errorMessage?:string):any=>({role:'assistant',content,api:'openai-responses',provider:'openai',model:'gpt-4o-mini',usage:{input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}},stopReason,errorMessage,timestamp:0});
const user=new UserMessageComponent('hello');out('user',user.render(20));user.setOutputPad(0);out('user-pad0',user.render(20));
const assistant=new AssistantMessageComponent();
assistant.updateContent(message([{type:'text',text:'  hello **world**  '}]),false);out('text',assistant.render(20));
assistant.updateContent(message([{type:'thinking',thinking:'  first thought  '},{type:'thinking',thinking:'second thought'},{type:'text',text:'answer'}]),false);out('thinking',assistant.render(20));
assistant.setHideThinkingBlock(true);out('hidden',assistant.render(20));
assistant.updateContent(message([{type:'text',text:'partial'}]),true);out('stream',assistant.render(20));
assistant.updateContent(message([{type:'text',text:'partial answer'}]),false);out('complete',assistant.render(20));
assistant.updateContent(message([{type:'text',text:'partial answer'}]),false);out('ai-adapter',assistant.render(20));
assistant.updateContent(message([{type:'text',text:'partial'}],'length'),false);out('length',assistant.render(20));
assistant.updateContent(message([{type:'text',text:'partial'}],'aborted','Request was aborted'),false);out('aborted',assistant.render(20));
assistant.updateContent(message([{type:'text',text:'partial'}],'error','network failed'),false);out('error',assistant.render(20));
assistant.updateContent(message([{type:'text',text:'calling tool'},{type:'toolCall',id:'x',name:'read',arguments:{}}],'error','network failed'),false);out('tool-error',assistant.render(20));
