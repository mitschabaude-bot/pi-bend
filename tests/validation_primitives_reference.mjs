import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=fs.readFileSync('../pi-mono/packages/ai/src/utils/validation.ts','utf8');
const start=source.indexOf('function getSchemaTypes(');
const end=source.indexOf('function getSubSchemaValidator(',start);
if(start<0||end<=start)throw new Error('validation helper block missing');
const helpers=new Function(stripTypeScriptTypes(source.slice(start,end))+';return {getSchemaTypes,matchesJsonType};')();
function build(v){
 switch(v[0]){
  case 'null': return null;
  case 'boolean': return v[1];
  case 'number': {const b=Buffer.from(v[1],'hex');return b.readDoubleBE();}
  case 'string': return String.fromCodePoint(...v[1]);
  case 'array': return v[1].map(build);
  case 'object': return {};
 }
}
const input=JSON.parse(fs.readFileSync(0,'utf8'));
console.log(JSON.stringify({
 matches: input.values.map(v=>input.kinds.map(k=>helpers.matchesJsonType(build(v),k))),
 types: input.schemas.map(v=>helpers.getSchemaTypes({type:build(v)})),
 missing: helpers.getSchemaTypes({}),
}));
