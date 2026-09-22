// Execute the pinned assertions and record every pure public call as an oracle.
import { mock, expect } from 'bun:test';
import { readFileSync } from 'node:fs';
const root = process.argv[2];
const actual = {...await import(root+'/src/core/prompt-templates.ts')};
const captured: unknown[] = [];
const wrappers = Object.fromEntries(['parseCommandArgs','substituteArgs','expandPromptTemplate'].map(kind => [kind,(...args: unknown[]) => {
  const expected = actual[kind](...args);
  captured.push({kind,args,expected});
  return expected;
}]));
mock.module(root+'/src/core/prompt-templates.ts',()=>({...actual,...wrappers}));
let skip=false;
mock.module('vitest',()=>({expect,afterAll:()=>{},describe:(name:string,fn:()=>void)=>{
  const previous=skip;skip=name.startsWith('loadPromptTemplates');fn();skip=previous;
},test:(_name:string,fn:()=>void)=>{if(!skip)fn();}}));
await import(root+'/test/prompt-templates.test.ts');
for(const c of JSON.parse(readFileSync(process.argv[3],'utf8'))){captured.push({...c,expected:actual[c.kind](...c.args)});}
console.log(JSON.stringify(captured));
