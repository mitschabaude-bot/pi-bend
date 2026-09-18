import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=fs.readFileSync('../pi-mono/packages/ai/src/utils/validation.ts','utf8');
function block(startText,endText){
 const start=source.indexOf(startText),end=source.indexOf(endText,start);
 if(start<0||end<=start)throw new Error('upstream coercion block missing');
 return stripTypeScriptTypes(source.slice(start,end));
}
const functions=block('function getSchemaTypes(', 'function getSubSchemaValidator(')+block('function coercePrimitiveByType(', 'function applySchemaObjectCoercion(');
const selection=block('const schemaTypes = getSchemaTypes(schema);','\n\tif (\n\t\tschemaTypes.includes("object")');
const select=new Function('value','schema',functions+'let nextValue=value;'+selection+'return nextValue;');
function build(v){
 switch(v[0]){
  case 'undefined': return undefined;
  case 'null': return null;
  case 'boolean': return v[1];
  case 'number': return Buffer.from(v[1],'hex').readDoubleBE();
  case 'string': return String.fromCodePoint(...v[1]);
  case 'array': return v[1].map(build);
  case 'object': {const o=Object.create(null);for(const [k,x,e] of v[1])Object.defineProperty(o,k,{value:build(x),enumerable:e});for(const [k,x]of v[2])o[Symbol.for(String(k))]=build(x);return o;}
  case 'symbol': return Symbol.for(String(v[1]));
  case 'callable': return ()=>{throw new Error('coercion invoked callable')};
  case 'bigint': return 1n;
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
console.log(JSON.stringify(input.values.map(tagged=>input.types.map(type=>{const original=build(tagged),result=select(original,{type});return Object.is(original,result)?tagged:wire(result);}))))
