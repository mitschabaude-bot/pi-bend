import fs from 'node:fs';
import { validatePositiveInteger } from '/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai/internal/utils/values.mjs';
import OpenAI from '/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai/index.mjs';
const root='/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai/';
const version=JSON.parse(fs.readFileSync(root+'package.json','utf8')).version;
if(version!=='6.40.0')throw Error(version);
const words=JSON.parse(fs.readFileSync(0,'utf8'));
const messages=words.map(([high,low])=>{
 const view=new DataView(new ArrayBuffer(8));view.setUint32(0,high);view.setUint32(4,low);
 try{validatePositiveInteger('timeout',view.getFloat64(0));return 'valid';}catch(error){return error.message;}
});
let authentication;
try{Object.create(OpenAI.prototype).validateHeaders({values:new Headers(),nulls:new Set()});}catch(error){authentication=error.message;}
console.log(JSON.stringify({version,messages,authentication}));
