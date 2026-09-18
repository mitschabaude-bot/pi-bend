import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const helper=fs.readFileSync('../pi-mono/packages/ai/src/api/constrained-sampling.ts','utf8');
const shared=fs.readFileSync('../pi-mono/packages/ai/src/api/openai-responses-shared.ts','utf8');
const start=shared.indexOf('export function convertResponsesTools(');
const end=shared.indexOf('// Stream processing',start);
const code=stripTypeScriptTypes(helper+'\n'+shared.slice(start,end)).replace(/^export /gm,'');
const api=new Function(code+';return {convertResponsesTools,createGrammarToolInputProperties,resolveGrammarConstrainedSampling};')();
const result=fn=>{try{return {ok:true,value:fn()??null}}catch(e){return {ok:false,error:e.message}}};
let input='';for await(const chunk of process.stdin)input+=chunk;
process.stdout.write(JSON.stringify(JSON.parse(input).map(c=>({
 converted:result(()=>JSON.stringify(api.convertResponsesTools(c.tools??[],c.options??undefined))),
 properties:result(()=>Object.fromEntries(api.createGrammarToolInputProperties(c.tools??undefined,c.options?.supportsOpenAIGrammarTools??false))),
 grammars:(c.tools??[]).map(tool=>result(()=>api.resolveGrammarConstrainedSampling(tool,c.options?.supportsOpenAIGrammarTools??false)))
}))));
