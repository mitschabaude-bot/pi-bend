// Host oracle for the native listener collection/traversal tests. Complete
// EventTarget flags, signal options and exception reporting remain pending.
import assert from "node:assert/strict";

const add = (id, options = {}, type = "abort") => ["add", type, id, options];
const remove = (id, capture = false, type = "abort") => ["remove", type, id, { capture }];
const dispatch = (type = "abort") => ["dispatch", type];
const cases = [
  {
    name: "duplicate registration preserves the original once flag",
    callbacks: { a: [] },
    actions: [add("a"), add("a", { once: true }), dispatch(), dispatch()],
    trace: ["a", "a"],
  },
  {
    name: "capture distinguishes registrations and removals",
    callbacks: { a: [] },
    actions: [add("a"), add("a", { capture: true }), dispatch(), remove("a"), dispatch()],
    trace: ["a", "a", "a"],
  },
  {
    name: "event types distinguish otherwise identical registrations",
    callbacks: { a: [] },
    actions: [add("a"), add("a", {}, "other"), remove("a"), dispatch(), dispatch("other")],
    trace: ["a"],
  },
  {
    name: "once removal happens before reentrant dispatch",
    callbacks: { a: [dispatch()], b: [] },
    actions: [add("a", { once: true }), add("b"), dispatch(), dispatch()],
    trace: ["a", "b", "b", "b"],
  },
  {
    name: "removing a later listener suppresses its pending invocation",
    callbacks: { a: [remove("b")], b: [], c: [] },
    actions: [add("a"), add("b"), add("c"), dispatch()],
    trace: ["a", "c"],
  },
  {
    name: "addition from the only listener waits for the next dispatch",
    callbacks: { a: [add("b")], b: [] },
    actions: [add("a"), dispatch(), dispatch()],
    trace: ["a", "a", "b"],
  },
  {
    name: "addition before an existing tail is visited in the same dispatch",
    callbacks: { a: [add("c")], b: [], c: [] },
    actions: [add("a"), add("b"), dispatch()],
    trace: ["a", "b", "c"],
  },
  {
    name: "remove and re-add follows the live chain rather than a snapshot",
    callbacks: { a: [remove("b"), add("b")], b: [], c: [] },
    actions: [add("a", { once: true }), add("b"), add("c"), dispatch()],
    trace: ["a", "c", "b"],
  },
  {
    name: "replacing the emptied list does not reconnect the old traversal",
    callbacks: { a: [remove("a"), remove("b"), add("c")], b: [], c: [] },
    actions: [add("a"), add("b"), dispatch(), dispatch()],
    trace: ["a", "c"],
  },
  {
    name: "cached removed nodes preserve links through removed successors",
    callbacks: { a: [remove("b"), remove("c")], b: [], c: [], d: [] },
    actions: [add("a"), add("b"), add("c"), add("d"), dispatch()],
    trace: ["a", "d"],
  },
  {
    name: "replacing a cached tail does not connect its old next link",
    callbacks: { a: [remove("b"), add("c")], b: [], c: [] },
    actions: [add("a"), add("b"), dispatch(), dispatch()],
    trace: ["a", "a", "c"],
  },
  {
    name: "nested and outer traversal both see an appended live tail",
    callbacks: { a: [add("c"), dispatch()], b: [], c: [] },
    actions: [add("a", { once: true }), add("b"), dispatch()],
    trace: ["a", "b", "c", "b", "c"],
  },
];

// Reproducible mutation sequences broaden type/capture/once/identity coverage.
// Callback mutations only remove, so dispatch is finite without a fuel limit.
let seed = 0x41626f72;
const random = (bound) => {
  seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
  return (seed >>> 8) % bound;
};
const ids = ["a", "b", "c", "d"];
const types = ["abort", "other", "🐱"];
for (let i = 0; i < 24; i++) {
  const callbacks = Object.fromEntries(ids.map(id => [id, []]));
  for (const id of ids) {
    const count = random(3);
    for (let j = 0; j < count; j++) {
      callbacks[id].push(remove(ids[random(ids.length)], !!random(2), types[random(types.length)]));
    }
  }
  const actions = [];
  for (let j = 0; j < 48; j++) {
    const type = types[random(types.length)];
    const id = ids[random(ids.length)];
    switch (random(4)) {
      case 0: actions.push(remove(id, !!random(2), type)); break;
      case 1: actions.push(dispatch(type)); break;
      default: actions.push(add(id, { capture: !!random(2), once: !!random(2), passive: !!random(2) }, type)); break;
    }
  }
  actions.push(...types.map(type => dispatch(type)));
  cases.push({ name: `seeded listener mutation ${i}`, callbacks, actions });
}

for (const fixture of cases) {
  const target = new EventTarget();
  const trace = [];
  const callbacks = Object.fromEntries(Object.entries(fixture.callbacks).map(([id, actions]) => [id, () => {
    trace.push(id);
    for (const action of actions) run(action);
  }]));
  function run([operation, type, id, options]) {
    switch (operation) {
      case "add": target.addEventListener(type, callbacks[id], options); break;
      case "remove": target.removeEventListener(type, callbacks[id], options); break;
      case "dispatch": target.dispatchEvent(new Event(type)); break;
      default: throw new Error(`Unknown operation: ${operation}`);
    }
  }
  for (const action of fixture.actions) run(action);
  if (fixture.trace !== undefined) assert.deepEqual(trace, fixture.trace, fixture.name);
  else fixture.trace = trace;
}
console.log(JSON.stringify({ node: process.version, cases }));
