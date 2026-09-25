import { UPSTREAM } from "./upstream_pin.mjs";
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const { loadThemeFromPath } = await import(UPSTREAM + '/packages/coding-agent/src/modes/interactive/theme/theme.ts');

const root=UPSTREAM + '/packages/coding-agent/src/modes/interactive/theme/';
const source=readFileSync(root+'theme.ts','utf8');
assert.equal(createHash('sha256').update(source).digest('hex'),'c3bf2e3b72f6bb782f34de0535fcc1758b9b6ea7a0d2e7d6f17244fa55c3f31a');
const [file,mode]=process.argv.slice(2);
const json=JSON.parse(readFileSync(file,'utf8').replace(/^\uFEFF/,''));
const theme=loadThemeFromPath(file,mode as 'truecolor'|'256color');
const colors={...json.colors,
  scrollbarTrack:json.colors.scrollbarTrack??json.colors.muted,
  scrollbarThumb:json.colors.scrollbarThumb??json.colors.text,
  thinkingMax:json.colors.thinkingMax??json.colors.thinkingXhigh,
  searchMatchBg:json.colors.searchMatchBg??json.colors.selectedBg,
  searchMatchText:json.colors.searchMatchText??json.colors.text,
};
const bg=new Set(['selectedBg','searchMatchBg','userMessageBg','customMessageBg','toolPendingBg','toolSuccessBg','toolErrorBg']);
console.log('N|'+theme.name);
for(const key of Object.keys(colors).filter(key=>!bg.has(key))) console.log('F|'+key+'|'+theme.getFgAnsi(key as never));
for(const key of Object.keys(colors).filter(key=>bg.has(key))) console.log('B|'+key+'|'+theme.getBgAnsi(key as never));
