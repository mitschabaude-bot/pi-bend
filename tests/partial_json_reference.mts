import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {createRequire,stripTypeScriptTypes} from 'node:module';
const require=createRequire(import.meta.url);
const packagePath=process.env.PI_PARTIAL_JSON_PACKAGE??'/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/partial-json';
const meta=JSON.parse(fs.readFileSync(packagePath+'/package.json','utf8'));
if(meta.version!=='0.1.7')throw Error('Expected Pi-pinned partial-json 0.1.7');
const partialParse=require(packagePath+'/dist/index.js').parse;
const source=fs.readFileSync(UPSTREAM + '/packages/ai/src/utils/json-parse.ts','utf8');
const code=stripTypeScriptTypes(source).replace(/^import .*;$/gm,'').replace(/^export /gm,'');
const streaming=new Function('partialParse',code+';return parseStreamingJson;')(partialParse);
const encode=value=>{
 if(value===null)return {null:true};
 if(typeof value==='number'){const bytes=new DataView(new ArrayBuffer(8));bytes.setFloat64(0,value);return {number:[bytes.getUint32(0),bytes.getUint32(4)]};}
 if(typeof value==='string')return {text:value};
 if(typeof value==='boolean')return {boolean:value};
 if(Array.isArray(value))return {array:value.map(encode)};
 return {object:Object.entries(value).map(([key,v])=>[key,encode(v)])};
};
let input='';for await(const chunk of process.stdin)input+=chunk;
process.stdout.write(JSON.stringify(JSON.parse(input).map(text=>{
 let raw;try{raw={ok:true,value:encode(partialParse(text??undefined))};}catch{raw={ok:false};}
 return {raw,streaming:encode(streaming(text??undefined))};
})));
