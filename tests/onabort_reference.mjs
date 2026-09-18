const sequences = [
  [['set',1],['abort'],['set',3],['abort'],['fire']],
  [['add',0],['set',1],['add',2],['set',3],['fire']],
  [['set',null],['add',0],['set',1],['fire']],
  [['set',1],['add',2],['set',null],['fire'],['set',3],['fire']],
  [['set',1],['add',1],['remove',1],['fire']],
  [['add',1],['set',1],['fire']],
  [['add',0],['set',1],['add',2],['fire']],
  [['add',0],['set',null],['add',2],['fire']],
];
const cases = [];
for (let mode = 0; mode < 4; mode++) for (const actions of sequences) {
  const controller = new AbortController(), signal = controller.signal, trace = [], errors = [];
  const onError = error => errors.push(error.message);
  process.on('uncaughtException', onError);
  const callbacks = Array.from({length:4}, (_, id) => function(event) {
    if (this !== signal || event.target !== signal) throw new Error('receiver identity');
    trace.push(`${id}:${event.eventPhase}:${event.currentTarget === signal}`);
    if (id === 1 && mode === 3) throw new Error('handler failure');
    if (id === 0 && (mode === 1 || mode === 2)) signal.onabort = mode === 1 ? callbacks[3] : null;
  });
  const getter = () => trace.push('get:' + (signal.onabort === null ? 'null' : callbacks.indexOf(signal.onabort)));
  getter();
  for (const [op, value] of actions) {
    if (op === 'add') signal.addEventListener('abort', callbacks[value]);
    if (op === 'remove') signal.removeEventListener('abort', callbacks[value]);
    if (op === 'set') signal.onabort = value === null ? null : callbacks[value];
    if (op === 'abort') controller.abort(0);
    if (op === 'fire') trace.push('result:' + signal.dispatchEvent(new Event('abort')));
    getter();
  }
  await new Promise(resolve => setImmediate(resolve));
  process.removeListener('uncaughtException', onError);
  cases.push({mode, actions, trace, errors});
}
console.log(JSON.stringify({node:process.version, cases}));
