import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import assert from 'node:assert/strict';
const source=fs.readFileSync(UPSTREAM + '/packages/ai/src/api/transform-messages.ts','utf8');
const transform=new Function(stripTypeScriptTypes(source).replace(/^export /gm,'')+';return transformMessages;')();
let input='';for await(const chunk of process.stdin)input+=chunk;
process.stdout.write(JSON.stringify(JSON.parse(input).map(({content,api,provider,model})=>{
 const original={role:'assistant',content,api,provider,model,responseModel:'response-model',responseId:'response-id',providerThinkingLevel:'high',usage:{totalTokens:42},stopReason:'stop',errorMessage:'metadata',rawStopReason:'raw',endTurn:false,timestamp:17};
 const result=transform([original],{id:'test',api:'openai-responses',provider:'test-provider',input:['text','image']})[0];
 const {content:resultContent,...metadata}=result;const {content:_,...expected}=original;assert.deepEqual(metadata,expected);
 return resultContent;
})));
