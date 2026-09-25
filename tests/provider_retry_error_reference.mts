import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=stripTypeScriptTypes(fs.readFileSync(UPSTREAM + '/packages/ai/src/utils/provider-retry.ts','utf8')).replace(/^export /gm,'');
const helpers=new Function(source+'\nreturn {validateServerRetryDelayMs,createAbortError};')();
function number(hi,lo){const b=Buffer.alloc(8);b.writeUInt32BE(Number(hi));b.writeUInt32BE(Number(lo),4);return b.readDoubleBE();}
function bits(n){if(Number.isNaN(n))return 'nan';const b=Buffer.alloc(8);b.writeDoubleBE(n);return b.readUInt32BE(0)+':'+b.readUInt32BE(4);}
const cases=JSON.parse(fs.readFileSync(0,'utf8'));
console.log(JSON.stringify(cases.map(c=>{
 const [mode,hi,lo,mh,ml]=c.split(';');
 if(mode==='c')return bits(Math.ceil(number(hi,lo)));
 if(mode==='o'||mode==='p')return 'CustomError:original';
 if(mode==='a'||mode==='r'){const e=helpers.createAbortError();return e.name+':'+e.message;}
 try{helpers.validateServerRetryDelayMs(number(hi,lo),number(mh,ml),'provider failure 🙂');throw Error('fixture did not trigger limit');}
 catch(e){if(!e.message.startsWith('Server requested '))throw e;return e.name+':'+e.message;}
})));
