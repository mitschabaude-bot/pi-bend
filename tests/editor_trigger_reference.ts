// Evaluate the pinned editor's trigger and debounce patterns (test oracle only).
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2],extra=process.argv[3]??'';
function source(path:string){return readFileSync(resolve(root,path),'utf8');}
const editor=source('packages/tui/src/components/editor.ts');assert.equal(createHash('sha256').update(editor).digest('hex'),'241695859d48f49c6aaba9b9cfc14c6cd28639c6c247adb4fe2c202a9e2c6e20');
const utils=source('packages/tui/src/utils.ts');assert.equal(createHash('sha256').update(utils).digest('hex'),'8cda2d53e2361ac5aaf6d7345b2fee058c8df5743eae4e4e90c89a7072c026c3');
const slice=(text:string,start:string,end:string)=>{const a=text.indexOf(start),b=text.indexOf(end,a);assert.ok(a>=0&&b>a,start);return text.slice(a,b).replace(/^export /gm,'');};
const regexes=slice(utils,'export const cjkBreakRegex','function isPrintableAscii');
const patterns=new Bun.Transpiler({loader:'ts'}).transformSync(slice(editor,'const unquotedAutocompleteSuffixRegex','function createScrollBorder'));
const {buildTriggerPattern,buildDebouncePattern}=new Function(regexes+patterns+';return {buildTriggerPattern,buildDebouncePattern}')();
const triggers=['@','#'];for(const c of extra)if(c!=='/'&&!/\s/.test(c)&&!triggers.includes(c))triggers.push(c);
const trigger=buildTriggerPattern(triggers),debounce=buildDebouncePattern(triggers);
console.log(JSON.stringify(JSON.parse(readFileSync(0,'utf8')).map((text:string)=>({trigger:trigger.test(text),debounce:debounce.test(text)}))));
