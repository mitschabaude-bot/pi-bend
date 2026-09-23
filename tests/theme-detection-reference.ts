import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {
  detectTerminalBackgroundFromEnv, detectTerminalThemeForAuto,
  getThemeForRgbColor, resolveThemeSetting,
} from '/home/agent/code/pi-mono/packages/coding-agent/src/modes/interactive/theme/theme.ts';

const source=readFileSync('/home/agent/code/pi-mono/packages/coding-agent/src/modes/interactive/theme/theme.ts');
assert.equal(createHash('sha256').update(source).digest('hex'),'c3bf2e3b72f6bb782f34de0535fcc1758b9b6ea7a0d2e7d6f17244fa55c3f31a');
for(const value of ['light/dark',' a / b ','dark','','a/b/c','a/','/b'])
  console.log(`S|${value}|${resolveThemeSetting(value,'light')??'undefined'}|${resolveThemeSetting(value,'dark')??'undefined'}`);
function show(d: ReturnType<typeof detectTerminalBackgroundFromEnv>){return `${d.theme}|${d.source}|${d.detail}|${d.confidence}`;}
console.log('E||'+show(detectTerminalBackgroundFromEnv({env:{}})));
console.log('E|0;15;bad|'+show(detectTerminalBackgroundFromEnv({env:{COLORFGBG:'0;15;bad'}})));
for(const [scheme,background,env] of [
  ['light',{r:8,g:8,b:8},'0;0'],
  [undefined,{r:250,g:250,b:250},'0;0'],
  [undefined,undefined,'0;15'],
] as const){
  const result=await detectTerminalThemeForAuto({timeoutMs:1,env:{COLORFGBG:env},ui:{
    async queryTerminalColorScheme(){return scheme;},
    async queryTerminalBackgroundColor(){return background;},
  }});
  console.log('A|'+result);
}
for(let index=0;index<256;index++) console.log(`I|${index}|${show(detectTerminalBackgroundFromEnv({env:{COLORFGBG:`0;${index}`}}))}`);
const channels=[0,1,8,63,127,128,192,240,250,254,255];
for(const r of channels) for(const g of channels) for(const b of channels)
  console.log(`R|${r},${g},${b}|${getThemeForRgbColor({r,g,b})}`);
