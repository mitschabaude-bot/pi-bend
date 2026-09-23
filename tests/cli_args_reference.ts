// Run every pinned named assertion, while collecting full parser outputs.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const [modulePath, testsPath, extraPath] = process.argv.slice(2);
const upstream = await import(modulePath);
const records: Array<{name: string,input: unknown,expected: unknown}> = [];
const names: string[] = [];
let current = '';
const suites: string[] = [];
function describe(name: string,body:()=>void) { suites.push(name); body(); suites.pop(); }
function test(name: string,body:()=>void) { current=[...suites,name].join(' / '); names.push(current); body(); }
(test as any).each=(values:any[]) => (name:string,body:(value:any)=>void) => { for(const value of values) test(name.replace("%s",String(value)),()=>body(value)); };
function match(actual:any,wanted:any) { for (const [key,value] of Object.entries(wanted)) assert.deepEqual(actual[key],value); }
function expect(value:any) { return {
  toBe:(wanted:any)=>assert.strictEqual(value,wanted),
  toEqual:(wanted:any)=>assert.deepEqual(value,wanted),
  toContain:(wanted:any)=>assert.ok(value.includes(wanted)),
  toBeUndefined:()=>assert.strictEqual(value,undefined),
  toMatchObject:(wanted:any)=>match(value,wanted),
}; }
function parseArgs(input:string[]) {
  const value=upstream.parseArgs(input);
  records.push({name:current,input,expected:{...value,unknownFlags:[...value.unknownFlags]}});
  return value;
}
function normalizeSessionName(input:string) {
  const value=upstream.normalizeSessionName(input);
  records.push({name:current,input,expected:value ?? null});
  return value;
}
let tests=fs.readFileSync(testsPath,'utf8').replace(/^import .*;\n/gm,'');
new Function('describe','test','expect','parseArgs','normalizeSessionName',new Bun.Transpiler({loader:"ts"}).transformSync(tests))(describe,test,expect,parseArgs,normalizeSessionName);
current='supplemental differential';
for(const input of JSON.parse(fs.readFileSync(extraPath,'utf8'))) typeof input==='string'?normalizeSessionName(input):parseArgs(input);
console.log(JSON.stringify({names,records}));
