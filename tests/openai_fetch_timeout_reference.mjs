// Test-only SDK probe: injected fetch, no network or real credentials.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createHash} from 'node:crypto';
import OpenAI from '/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai/index.mjs';

const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const observations = [];
for (const rejects of [false, true]) {
  const parent = new AbortController();
  const child = new AbortController();
  const failure = new Error('injected fetch failure');
  const response = new Response('body');
  let received;
  const client = new OpenAI({apiKey: 'test-only', maxRetries: 0, fetch: async (_url, init) => {
    received = init;
    if (rejects) throw failure;
    return response;
  }});
  try {
    assert.equal(await client.fetchWithTimeout('https://example.invalid/responses', {
      method: 'post', signal: parent.signal, body: '{}',
    }, 20, child), response);
    assert.equal(rejects, false);
  } catch (error) {
    assert.equal(rejects, true);
    assert.equal(error, failure);
  }
  assert.equal(received.method, 'POST');
  assert.equal(received.signal, child.signal);
  await pause(50);
  assert.equal(child.signal.aborted, false);
  parent.abort('caller cancelled after headers');
  assert.equal(child.signal.aborted, true);
  observations.push({rejects, method: received.method, timerClearedAfterSettlement: true,
    parentStillForwardedAfterSettlement: true});
}
const sdk = '/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai/';
const sha = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
console.log(JSON.stringify({sdkVersion: JSON.parse(fs.readFileSync(sdk + 'package.json')).version,
  sources: Object.fromEntries([sdk + 'client.mjs', sdk + 'src/client.ts', new URL(import.meta.url).pathname].map(path => [path, sha(path)])),
  observations}, null, 2));
