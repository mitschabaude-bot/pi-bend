import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const { getCurrentTools, getToolStateChanges, toToolDeclaration } = await import(UPSTREAM + '/packages/ai/src/utils/transcript.ts');
const source=fs.readFileSync(UPSTREAM + '/packages/agent/src/agent-loop.ts','utf8');
const body=source.slice(source.indexOf('function declareToolChanges('),source.indexOf('\n/**\n * Stream an assistant response'));
let text=''; for await (const chunk of process.stdin) text+=chunk;
let nowCalls=0;
const run=new Function('getCurrentTools','getToolStateChanges','toToolDeclaration','Date',stripTypeScriptTypes(body)+';return declareToolChanges;')(getCurrentTools,getToolStateChanges,toToolDeclaration,{now:()=>{nowCalls++;return 777;}});
const results=JSON.parse(text).map(fixture=>{
  nowCalls=0;
  const value=run({messages:fixture.previous,tools:fixture.tools},fixture.pending);
  return {value,timestampNeeded:nowCalls!==0};
});
process.stdout.write(JSON.stringify(results));
