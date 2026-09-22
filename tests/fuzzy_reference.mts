import fs from 'node:fs';
import assert from 'node:assert/strict';
import {stripTypeScriptTypes} from 'node:module';
const root='../pi-mono/packages/tui/';
const code=stripTypeScriptTypes(fs.readFileSync(root+'src/fuzzy.ts','utf8')).replace(/^export /gm,'');
const api=new Function(code+';return {fuzzyMatch,fuzzyFilter}')();
const cases=[]; const names=[];
function fuzzyMatch(query,text){const expected=api.fuzzyMatch(query,text);cases.push({kind:'match',query,text,expected});return expected;}
function fuzzyFilter(items,query,getText){const expected=api.fuzzyFilter(items,query,getText);cases.push({kind:'filter',query,labels:items.map(getText),items,expected});return expected;}
const test=stripTypeScriptTypes(fs.readFileSync(root+'test/fuzzy.test.ts','utf8')).replace(/^import .*;$/gm,'');
new Function('assert','describe','it','fuzzyMatch','fuzzyFilter',test)(assert,(_name,fn)=>fn(),(name,fn)=>{fn();names.push(name)},fuzzyMatch,fuzzyFilter);
const originalCalls=cases.length;
for(const c of JSON.parse(fs.readFileSync(0,'utf8'))){if(c.kind==='match')fuzzyMatch(c.query,c.text);else fuzzyFilter(c.items,c.query,x=>x);}
console.log(JSON.stringify({names,originalCalls,cases}));
