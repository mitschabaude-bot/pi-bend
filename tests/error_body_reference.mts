import { readFileSync } from 'node:fs';
import { normalizeProviderError, formatProviderError } from '../../pi-mono/packages/ai/src/utils/error-body.ts';
const cases = JSON.parse(readFileSync(0, 'utf8'));
function body(value: any): any {
  if (value === null) return undefined;
  if (value[0] === 'unread') return {pipe() {}, _events: {close: [null]}};
  if (value[0] === 'private') return new class { locked = false; state = {}; }();
  return value[1];
}
console.log(JSON.stringify(cases.map((input: any[]) => {
  let error: any;
  let prefix: string | undefined;
  if (input.length === 3) {
    error = input[1]; prefix = input[2] ?? undefined;
  } else {
    const [status, message, bodies, p] = input;
    prefix = p ?? undefined;
    error = Object.assign(new Error(message), {
      status: status ?? undefined,
      body: body(bodies[0] ?? null),
      error: body(bodies[1] ?? null),
      $response: {body: body(bodies[2] ?? null)},
    });
  }
  const n = normalizeProviderError(error);
  return [n.status ?? null, n.body ?? null, n.message, n.messageCarriesBody, formatProviderError(n, prefix)];
})));
