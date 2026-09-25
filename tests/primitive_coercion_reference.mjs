import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=fs.readFileSync(UPSTREAM + '/packages/ai/src/utils/validation.ts','utf8');
const start=source.indexOf('function coercePrimitiveByType(');
const end=source.indexOf('function applySchemaObjectCoercion(',start);
if(start<0||end<=start)throw new Error('upstream primitive coercion block missing');
const coerce=new Function(stripTypeScriptTypes(source.slice(start,end))+';return coercePrimitiveByType;')();
function build(v){
 switch(v[0]){
  case 'null': return null;
  case 'boolean': return v[1];
  case 'number': return Buffer.from(v[1],'hex').readDoubleBE();
  case 'string': return String.fromCodePoint(...v[1]);
  case 'array': return v[1].map(build);
  case 'object': return Object.fromEntries(v[1].map(([key, value]) => [key, build(value)]));
 }
}
function wire(v){
 if(v===null)return ['null'];
 if(typeof v==='number'){const b=Buffer.alloc(8);b.writeDoubleBE(v);return ['number',b.toString('hex')];}
 if(typeof v==='boolean')return ['boolean',v];
 if(typeof v==='string')return ['string',Array.from(v,c=>c.codePointAt(0))];
 throw new Error('unexpected allocated object');
}
const input=JSON.parse(fs.readFileSync(0,'utf8'));
console.log(JSON.stringify(input.values.map(tagged=>input.kinds.map(kind=>{const original=build(tagged),result=coerce(original,kind);return Object.is(original,result)?tagged:wire(result);}))))
