// Test-only oracle: installed OpenAI SDK status handling plus pinned pi retry.
import fs from 'node:fs';
import { createRequire, stripTypeScriptTypes } from 'node:module';
const require = createRequire(import.meta.url);
const sdkPath = '/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai';
const { default: OpenAI } = require(sdkPath);
const version = JSON.parse(fs.readFileSync(sdkPath + '/package.json', 'utf8')).version;
if (version !== '6.40.0') throw new Error('Unexpected SDK version ' + version);
const source = stripTypeScriptTypes(fs.readFileSync('../pi-mono/packages/ai/src/utils/provider-retry.ts', 'utf8'))
  .replace(/^export /gm, '').replace('function abortableSleep(', 'function originalAbortableSleep(');
function bits(n) { const b = Buffer.alloc(8); b.writeDoubleBE(n); return b.readUInt32BE(0) + ':' + b.readUInt32BE(4); }
function scalars(text) { return [...text].map(c => c.codePointAt(0)).join(','); }
const cases = JSON.parse(fs.readFileSync(0, 'utf8'));
const results = [];
for (const c of cases) {
  const trace = [];
  const math = Object.create(Math); math.random = () => { trace.push('random'); return 0; };
  const sleep = async ms => { trace.push('sleep ' + bits(ms)); };
  const retry = new Function('Math', 'injectedSleep', source + '\nfunction abortableSleep(ms,signal){return injectedSleep(ms,signal);}\nreturn retryProviderRequest;')(math, sleep);
  let attempt = 0;
  const client = new OpenAI({ apiKey: 'fixture-only', maxRetries: 0, fetch: async () => {
    trace.push('request');
    const item = c.responses[attempt++];
    if (!item) throw new Error('Unexpected extra attempt');
    const response = new Response(item.status === 204 ? null : Buffer.from(item.body, 'hex'), { status: item.status, headers: item.headers });
    const read = response.text.bind(response);
    response.text = async () => {
      const body = await read();
      if (!response.ok) trace.push('diagnostic:' + item.status + ':' + scalars(body));
      return body;
    };
    return response;
  }});
  try {
    const { response } = await retry(() => client.responses.create({ model: 'fixture', input: 'fixture', stream: true }).withResponse(), { maxRetries: c.retries });
    trace.push('accepted:' + response.status);
    trace.push('text:' + scalars(await response.text()));
  } catch (error) {
    if (error instanceof OpenAI.APIError && error.status) trace.push('failed:status');
    else throw error;
  }
  if (attempt !== c.responses.length) throw new Error('Unused response');
  results.push({ name: c.name, trace });
}
console.log(JSON.stringify({ sdkVersion: version, results }));
