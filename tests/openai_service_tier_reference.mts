import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const path=UPSTREAM + '/packages/ai/src/api/openai-responses.ts';
const source=fs.readFileSync(path,'utf8');
const offset=source.indexOf('function getServiceTierCostMultiplier(');
if(offset<0)throw Error('service tier implementation not found');
const apply=new Function(stripTypeScriptTypes(source.slice(offset))+'\nreturn applyServiceTierPricing;')();
const read=pair=>{const b=Buffer.alloc(8);b.writeUInt32BE(pair[0]);b.writeUInt32BE(pair[1],4);return b.readDoubleBE();};
const write=n=>{if(Number.isNaN(n))return 'nan';const b=Buffer.alloc(8);b.writeDoubleBE(n);return b.readUInt32BE()+':'+b.readUInt32BE(4);};
const rows=JSON.parse(fs.readFileSync(0,'utf8'));
const results=rows.map(({model,tier,cost})=>{
 const [input,output,cacheRead,cacheWrite,total]=cost.map(read);
 const usage={input:13,output:17,cacheRead:19,cacheWrite:23,cacheWrite1h:29,totalTokens:31,cost:{input,output,cacheRead,cacheWrite,total}};
 apply(usage,tier===null?undefined:tier,{id:model});
 return Object.values(usage.cost).map(write).join(',');
});
console.log(JSON.stringify(results));
