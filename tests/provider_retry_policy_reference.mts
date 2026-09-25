import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=stripTypeScriptTypes(fs.readFileSync(UPSTREAM + '/packages/ai/src/utils/provider-retry.ts','utf8')).replace(/^export /gm,'').replace('function validateServerRetryDelayMs(', 'function originalValidateServerRetryDelayMs(');
let observed;
const dateRequested={};
let dateText;
const fakeDate={parse(text){dateText=text;throw dateRequested;},now(){throw Error('unexpected clock read');}};
let random=0;
const fakeMath=Object.create(Math);fakeMath.random=()=>random;
const helpers=new Function('Date','Math',`let observed; ${source}
function validateServerRetryDelayMs(delay,max,message){ observed=[delay,max??60000];return originalValidateServerRetryDelayMs(delay,max,message); }
return {isRetryableProviderError,getRetryDelayMs,validateServerRetryDelayMs,observed:()=>observed};`)(fakeDate,fakeMath);
function bits(n){if(Number.isNaN(n))return 'nan';const b=Buffer.alloc(8);b.writeDoubleBE(n);return b.readUInt32BE(0)+':'+b.readUInt32BE(4);}
function codes(text){return Array.from(text,c=>c.codePointAt(0)).join(',');}
const input=JSON.parse(fs.readFileSync(0,'utf8'));
console.log(JSON.stringify(input.map(c=>{
 if(c.mode==='p') return bits(Number.parseFloat(c.text));
 const max=c.max===null?undefined:Number(c.max);
 if(c.mode==='d'){
   try{return 'ok:'+bits(helpers.validateServerRetryDelayMs(Number(c.epoch)-Number(c.now),max,'failure'));}
   catch{const [delay,limit]=helpers.observed();return 'limit:'+bits(delay)+':'+bits(limit);}
 }
 random=Number(c.random);dateText=undefined;
 // These are normalized header values supplied at the native boundary. The
 // native HTTP Headers adapter itself is not covered by this policy oracle.
 const values={'x-should-retry':c.should,'retry-after-ms':c.ms,'retry-after':c.seconds};
 const error=Object.assign(new Error('failure'),{status:c.status===null?undefined:Number(c.status),headers:{get:name=>values[name]??null}});
 const eligible=helpers.isRetryableProviderError(error)?'1':'0';
 try{
   const delay=helpers.getRetryDelayMs(error,c.index,max);
   const hasMs=c.ms && !Number.isNaN(Number.parseFloat(c.ms));
   const server=hasMs || !!c.seconds;
   return eligible+'|'+(server?'ok:':'backoff:')+bits(delay);
 }catch(error){
   if(error===dateRequested)return eligible+'|date:'+codes(dateText);
   const [delay,limit]=helpers.observed();return eligible+'|limit:'+bits(delay)+':'+bits(limit);
 }
})));
