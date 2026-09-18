// Host oracle only. Native EventTarget dispatch is not implemented yet.
// These traces preserve observable Node behavior needed by abort listeners.
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
];

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
  assert.deepEqual(trace, fixture.trace, fixture.name);
}
console.log(JSON.stringify({ node: process.version, cases }));
