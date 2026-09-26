// Evaluate the pinned private cache functions, without copying their bodies.
import { UPSTREAM } from './upstream_pin.mjs';
const source = await Bun.file(UPSTREAM + '/packages/ai/src/api/openai-codex-responses.ts').text();
const start = source.indexOf('function requestBodyWithoutInput(');
const end = source.indexOf('async function* startWebSocketOutputOnFirstEvent(', start);
if (start < 0 || end < 0) throw new Error('Pinned cache functions not found');
const compiled = new Bun.Transpiler({loader:'ts'}).transformSync(source.slice(start, end));
const run = new Function('entry', 'body', compiled + '\nreturn {body:buildCachedWebSocketRequestBody(entry,body),retained:!!entry.continuation};');
const cases = JSON.parse(await new Response(Bun.stdin.stream()).text());
await Bun.write(Bun.stdout, JSON.stringify(cases.map((value:any)=>run({continuation:value.continuation},value.body)))+'\n');
