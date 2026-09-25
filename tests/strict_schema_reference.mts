import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=fs.readFileSync(UPSTREAM + '/packages/ai/src/api/constrained-sampling.ts','utf8');
const api=new Function(stripTypeScriptTypes(source).replace(/^export /gm,'')+';return {makeStrictJsonSchema,getJsonSchemaToolParameters,resolveJsonSchemaStrictSampling};')();
const result=fn=>{try{return {ok:true,value:fn()??null}}catch(e){return {ok:false,error:e.message}}};
let input='';for await(const chunk of process.stdin)input+=chunk;
process.stdout.write(JSON.stringify(JSON.parse(input).map(schema=>{
 const original=structuredClone(schema);
 const strict=result(()=>api.makeStrictJsonSchema(schema));
 const resolutions=[];
 for(const config of [undefined,false,{type:'json_schema',strict:'prefer'},{type:'json_schema',strict:'require'},{type:'grammar',variants:{}}])for(const supported of [false,true])resolutions.push(result(()=>api.resolveJsonSchemaStrictSampling({name:'sample_tool',description:'Sample tool',parameters:schema,constrainedSampling:config},supported)));
 if(JSON.stringify(original)!==JSON.stringify(schema))throw Error('upstream mutated original');
 return {strict,resolutions};
})));
