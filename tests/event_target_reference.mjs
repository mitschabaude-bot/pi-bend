const definitions = [
  ['cancel', 'noop', false, false, true, 1],
  ['cancel', 'noop', true, false, true, 1],
  ['cancel', 'noop', false, false, false, 1],
  ['stop', 'resetStop', false, false, true, 1],
  ['immediate', 'cancel', false, false, true, 2],
  ['throw', 'noop', true, false, true, 1],
  ['throw', 'throw', false, false, true, 1],
  ['recursive', 'noop', false, false, true, 1],
  ['throw', 'noop', false, true, true, 2],
  ['noop', 'cancel', false, true, true, 2],
];
const cases = [];
for (const [first, second, passive, once, cancelable, repeat] of definitions) {
  const target = new EventTarget();
  const event = new Event('x', { cancelable });
  const trace = [], errors = [];
  const captureError = error => errors.push(error.message);
  process.on('uncaughtException', captureError);
  const record = label => trace.push(`${label}:${event.eventPhase}:${event.defaultPrevented}:${event.cancelBubble}:${event.currentTarget === target}`);
  function handler(label, mode) {
    return function(received) {
      if (this !== target || received !== event || received.target !== target) throw new Error('identity mismatch');
      record(label + ' before');
      switch (mode) {
        case 'cancel': event.preventDefault(); break;
        case 'stop': event.stopPropagation(); break;
        case 'resetStop': event.cancelBubble = false; break;
        case 'immediate': event.stopImmediatePropagation(); break;
        case 'throw': throw new Error(label);
        case 'recursive':
          try { target.dispatchEvent(event); trace.push('recursive:succeeded'); }
          catch (error) { trace.push('recursive:' + error.code); }
          break;
        case 'noop': break;
        default: throw new Error('unknown mode');
      }
      record(label + ' after');
    };
  }
  target.addEventListener('x', handler('a', first), { passive, once });
  target.addEventListener('x', handler('b', second), { passive: false });
  for (let i = 0; i < repeat; i++) {
    trace.push('result:' + target.dispatchEvent(event));
    record('end');
  }
  await new Promise(resolve => setImmediate(resolve));
  process.removeListener('uncaughtException', captureError);
  cases.push({ first, second, passive, once, cancelable, repeat, trace, errors });
}
console.log(JSON.stringify({ node: process.version, cases }));
