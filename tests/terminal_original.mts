import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert';
import {mock} from 'node:test';
import {EventEmitter} from 'node:events';
import {stripTypeScriptTypes} from 'node:module';
const root=UPSTREAM + '/packages/tui/';
const strip=file=>stripTypeScriptTypes(fs.readFileSync(root+file,'utf8')).replace(/^import[\s\S]*?;\s*$/gm,'').replace(/^export /gm,'');
const BufferClass=new Function('EventEmitter',strip('src/stdin-buffer.ts')+';return StdinBuffer')(EventEmitter);
const stdout=new EventEmitter(),stdin=new EventEmitter();stdout.write=()=>true;stdin.pause=()=>{};
const processMock={platform:'linux',env:{},stdout,stdin,pid:123,kill(){}};
const names=['ProcessTerminal','resolveEscapeTimeoutMs','normalizeNativeShiftEnterInput','normalizeAppleTerminalInput'];
const terminal=new Function('process','fs','path','StdinBuffer','setKittyProtocolActive','isNativeModifierPressed','getNativePlatformHelper',strip('src/terminal.ts')+';return {'+names.join(',')+'}')(processMock,fs,path,BufferClass,()=>{},()=>false,()=>undefined);
const tests=[],calls=[];
const describe=(name,body)=>body();const it=(name,body)=>tests.push({name,body});
for(const name of names.slice(1)){
 const original=terminal[name];terminal[name]=(...args)=>{const result=original(...args);calls.push({name,args,result});return result};
}
new Function('assert','describe','it','mock','process','setKittyProtocolActive',...names,strip('test/terminal.test.ts'))(assert,describe,it,mock,processMock,()=>{},...names.map(n=>terminal[n]));
for(const test of tests){await test.body();mock.timers.reset();mock.restoreAll()}
console.log(JSON.stringify({names:tests.map(t=>t.name),calls}));
