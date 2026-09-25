import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import { createRequire } from 'node:module';
const { normalizeProviderError, formatProviderError } = await import(UPSTREAM + '/packages/ai/src/utils/error-body.ts');
const require = createRequire(import.meta.url);
const path = '/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai';
const { APIError } = require(path);
const version = JSON.parse(fs.readFileSync(path + '/package.json', 'utf8')).version;
if (version !== '6.40.0') throw new Error('Unexpected SDK version ' + version);
function scalars(text) { return [...text].map(c => c.codePointAt(0)).join(','); }
function optional(text) { return text === undefined || text === null ? 'none' : 'some:' + scalars(text); }
function json(value) { return value === undefined ? 'none' : optional(JSON.stringify(value)); }
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
const results = input.map(c => {
  let parsed;
  try { parsed = JSON.parse(c.raw); } catch { parsed = undefined; }
  const headers = new Headers();
  if (c.id !== '-') headers.set('x-request-id', c.id);
  // Exact status-error construction used by client.mjs with SDK retries off.
  const error = APIError.generate(c.status, parsed, parsed ? undefined : c.raw, headers);
  const prefix = (c.provider === 'openai' ? 'OpenAI' : c.provider) + ' API error';
  return ['case', 'kind:' + error.constructor.name, 'status:' + error.status,
    'request-id:' + optional(error.requestID), 'code:' + json(error.code),
    'param:' + json(error.param), 'type:' + json(error.type),
    'message:' + scalars(error.message),
    'format:' + scalars(formatProviderError(normalizeProviderError(error), prefix))];
});
console.log(JSON.stringify({ version, results }));
