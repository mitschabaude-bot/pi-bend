// Host-runtime oracle, not a pi-mono test or production implementation.
const cases = [];
for (let mode = 0; mode < 6; mode++) {
  for (const once of [false, true]) for (const passive of [false, true]) {
    const controller = new AbortController(), signal = controller.signal;
    const trace = [], errors = [];
    let retained;
    const captureError = error => errors.push(error.message);
    process.on('uncaughtException', captureError);
    const state = label => trace.push(`${label}:${signal.aborted}:${signal.reason === undefined ? 'none' : signal.reason}`);
    const record = (label, event) => trace.push(`${label}:${event.type}:${event.isTrusted}:${event.bubbles}:${event.cancelable}:${event.composed}:${event.defaultPrevented}:${event.eventPhase}:${event.currentTarget === signal}:${event.target === signal}`);
    function b(event) { record('b', event); state('b state'); }
    function a(event) {
      if (this !== signal || event.target !== signal) throw new Error('identity mismatch');
      if (event.isTrusted) retained = event;
      record('a', event); state('a state');
      event.preventDefault();
      if (mode === 1) throw new Error('a failure');
      if (mode === 2) event.stopImmediatePropagation();
      if (mode === 3) { controller.abort(99); state('reentrant'); }
      if (mode === 5) signal.removeEventListener('abort', b);
    }
    signal.addEventListener('abort', a, { once, passive });
    signal.addEventListener('abort', b);
    state('before');
    if (mode === 4) {
      trace.push('manual:' + signal.dispatchEvent(new Event('abort')));
      state('after manual');
    }
    controller.abort(0); state('after');
    controller.abort(99); controller.abort(); state('repeat');
    signal.addEventListener('abort', function late() { trace.push('late'); });
    controller.abort(100); state('late registration');
    if (retained) record('retained', retained);
    await new Promise(resolve => setImmediate(resolve));
    process.removeListener('uncaughtException', captureError);
    cases.push({ mode, once, passive, trace, errors });
  }
}
console.log(JSON.stringify({ node: process.version, cases }));
