import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=fs.readFileSync('../pi-mono/packages/ai/src/api/constrained-sampling.ts','utf8');
const api=new Function(stripTypeScriptTypes(source).replace(/^export /gm,'')+';return {appendGrammarToolInputJsonDelta,getGrammarToolInput};')();
let input='';for await(const chunk of process.stdin)input+=chunk;
const data=JSON.parse(input);
const sequences=data.sequences.map(c=>{
 const buffer=structuredClone(c.buffer);
 return c.steps.map(s=>{
  let result;
  try{result={ok:true,delta:api.appendGrammarToolInputJsonDelta(buffer,s.property,s.next,s.close)??null};}
  catch(error){result={ok:false,error:error.message};}
  return {...result,buffer:structuredClone(buffer)};
 });
});
const arguments_=data.arguments.map(c=>{
 try{return {ok:true,value:api.getGrammarToolInput(c.name,c.arguments,c.property)}}
 catch(error){return {ok:false,error:error.message}}
});
process.stdout.write(JSON.stringify({sequences,arguments:arguments_}));
