// Execute the pinned assertions and record every pure public call as an oracle.
import { mock, expect } from 'bun:test';
import { readFileSync } from 'node:fs';
import * as filesystem from 'node:fs';
import { execFileSync } from 'node:child_process';
const root = process.argv[2];
const actual = {...await import(root+'/src/core/prompt-templates.ts')};
if (process.argv[4] === 'load') {
  // Bun returns raw OS order here; Pi's Node runtime uses libuv enumeration.
  // Get the order from Node itself, retaining the real filesystem Dirents.
  const fs={...filesystem};
  mock.module('fs',()=>({...fs,readdirSync:(path:string, options:unknown)=>{
    const entries=fs.readdirSync(path,options as any) as any[];
    const names=JSON.parse(execFileSync('node',['--input-type=module','-e',
      'import {readdirSync} from "node:fs"; console.log(JSON.stringify(readdirSync(process.argv[1])));',path],{encoding:'utf8'}));
    const byName=new Map(entries.map(e=>[typeof e==='string'?e:e.name,e]));
    return names.map((name:string)=>byName.get(name));
  }}));
  const options=JSON.parse(readFileSync(process.argv[3],'utf8'));
  console.log(JSON.stringify(actual.loadPromptTemplates(options)));
  process.exit(0);
}
const captured: unknown[] = [];
let origin="original";
const wrappers = Object.fromEntries(['parseCommandArgs','substituteArgs','expandPromptTemplate'].map(kind => [kind,(...args: unknown[]) => {
  const expected = actual[kind](...args);
  captured.push({origin,kind,args,expected});
  return expected;
}]));
mock.module(root+'/src/core/prompt-templates.ts',()=>({...actual,...wrappers}));
let skip=false;
mock.module('vitest',()=>({expect,afterAll:()=>{},describe:(name:string,fn:()=>void)=>{
  const previous=skip;skip=name.startsWith('loadPromptTemplates');fn();skip=previous;
},test:(_name:string,fn:()=>void)=>{if(!skip)fn();}}));
await import(root+'/test/prompt-templates.test.ts');
origin="generated";
for(const c of JSON.parse(readFileSync(process.argv[3],'utf8'))){captured.push({origin,...c,expected:actual[c.kind](...c.args)});}
console.log(JSON.stringify(captured));
