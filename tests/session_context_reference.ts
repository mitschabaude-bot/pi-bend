import {mock,expect} from 'bun:test';
import {readFileSync} from 'node:fs';
const root=process.argv[2];
const actual={...await import(root+'/src/core/session-manager.ts')};
const captured:unknown[]=[];
let origin="original";
const wrappers=Object.fromEntries(['buildSessionContext','buildContextEntries'].map(kind=>[kind,(...args:unknown[])=>{
 const expected=actual[kind](...args);captured.push({origin,kind,args:args[1]===undefined?[args[0]]:[args[0],args[1]],expected});return expected;
}]));
mock.module(root+'/src/core/session-manager.ts',()=>({...actual,...wrappers}));
// An installed vitest resolves to its own path, which a bare-name mock misses.
const vitestFactory=()=>({expect,describe:(_name:string,fn:()=>void)=>fn(),it:(_name:string,fn:()=>void)=>fn()});
mock.module('vitest',vitestFactory);
try{mock.module(Bun.resolveSync('vitest',root+'/test'),vitestFactory)}catch{};
await import(root+'/test/session-manager/build-context.test.ts');
origin="generated";
for(const c of JSON.parse(readFileSync(process.argv[3],'utf8')))captured.push({origin,...c,expected:actual[c.kind](...c.args)});
console.log(JSON.stringify(captured));
