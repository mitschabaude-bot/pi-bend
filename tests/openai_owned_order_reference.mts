// Read-only reference: the installed SDK constructs a request before fetch;
// pi's pinned retry wrapper then gives an observed abort precedence on failure.
import fs from 'node:fs';
import crypto from 'node:crypto';
import {retryProviderRequest} from '../../pi-mono/packages/ai/src/utils/provider-retry.ts';
const root = '/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai';
const {OpenAI} = await import(root + '/client.mjs');
const runs = [];
for (const [valid, aborted] of [[false, false], [false, true], [true, true]]) {
  let fetches = 0;
  const controller = new AbortController();
  if (aborted) controller.abort('stop');
  const client = new OpenAI({apiKey: 'fixture-key', baseURL: valid ? 'http://127.0.0.1:9/v1' : 'not a URL', maxRetries: 0,
    fetch: async () => { fetches++; throw new Error('unexpected fetch'); }});
  try {
    await retryProviderRequest(() => client.responses.create({model: 'fixture', input: 'hello'}, {signal: controller.signal}), {signal: controller.signal});
    throw new Error('invalid URL succeeded');
  } catch (error) {
    if (fetches !== 0 || (aborted ? error.name !== 'AbortError' : !error.message.includes('URL'))) throw error;
    runs.push({valid, aborted, fetches, name: error.name, message: error.message});
  }
}
const digest = path => crypto.createHash('sha256').update(fs.readFileSync(path)).digest('hex');
console.log(JSON.stringify({node: process.version, sdk: JSON.parse(fs.readFileSync(root+'/package.json','utf8')).version,
  sources: Object.fromEntries([root+'/client.mjs', '../pi-mono/packages/ai/src/utils/provider-retry.ts'].map(path=>[path,digest(path)])), runs}));
