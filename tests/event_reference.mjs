// Real Node Event property/method traces. Lifecycle hook steps describe the
// dispatcher around callbacks; this oracle does not replace an EventTarget port.
import assert from "node:assert/strict";
const listenerErrors = [];
const captureError = error => listenerErrors.push(error.message);
process.on("uncaughtException", captureError);
const definitions = [];
for (let mask = 0; mask < 8; mask++) {
  definitions.push({
    name: `constructor flags ${mask}`,
    init: { bubbles: !!(mask & 1), cancelable: !!(mask & 2), composed: !!(mask & 4) },
    before: [],
    listeners: [{ passive: false, actions: [["prevent"], ["return", true], ["stop"], ["bubble", false]] }],
    after: [["init", "hidden", false, false], ["init", "restored", true, true]],
  });
}
for (let mask = 0; mask < 4; mask++) {
  definitions.push({
    name: `passive listeners and callback phase ${mask}`,
    init: { bubbles: true, cancelable: true, composed: true },
    before: [],
    listeners: [
      { passive: !!(mask & 1), actions: [["prevent"], ["init", "ignored", false, false], ["recursive"]] },
      { passive: !!(mask & 2), actions: [["return", false], ["init", "changed", false, true]] },
    ],
    after: [["bubble", true], ["bubble", false], ["return", true]],
  });
}
definitions.push({
  name: "pre-dispatch immediate stop and hidden cancellation survive initEvent",
  init: { bubbles: false, cancelable: true, composed: true },
  before: [["prevent"], ["immediate"], ["bubble", false]],
  listeners: [{ passive: false, actions: [["init", "must not run", false, false]] }],
  after: [["init", "hidden", true, false], ["init", "visible", false, true]],
});
definitions.push({
  name: "stopPropagation still permits subsequent listeners",
  init: { bubbles: false, cancelable: false, composed: false }, before: [],
  listeners: [{ passive: true, actions: [["stop"]] }, { passive: false, actions: [["bubble", false]] }], after: [],
});
definitions.push({
  name: "stopImmediatePropagation suppresses subsequent listeners",
  init: { bubbles: false, cancelable: true, composed: false }, before: [],
  listeners: [{ passive: false, actions: [["immediate"]] }, { passive: true, actions: [["prevent"]] }], after: [],
});
definitions.push({
  name: "empty dispatch assigns target and clears phase",
  init: { bubbles: false, cancelable: true, composed: false }, before: [], listeners: [], after: [["prevent"]],
});
definitions.push({
  name: "throwing passive listener keeps dispatch guard and clears passive state",
  init: { bubbles: false, cancelable: true, composed: false }, before: [],
  listeners: [
    { passive: true, actions: [["prevent"], ["throw"]] },
    { passive: false, actions: [["prevent"], ["recursive"]] },
  ], after: [],
});

const cases = definitions.map(definition => {
  const target = new EventTarget(), other = new EventTarget();
  const event = new Event("original", definition.init);
  const stamp = event.timeStamp;
  const steps = [];
  const identity = value => value === null ? 0 : value === target ? 1 : value === other ? 2 : -1;
  function checkpoint() {
    steps.push(["check", {
      eventType: event.type, bubbles: event.bubbles, cancelable: event.cancelable,
      composed: event.composed, defaultPrevented: event.defaultPrevented,
      timeStampStable: event.timeStamp === stamp, target: identity(event.target),
      currentTarget: identity(event.currentTarget), srcElement: identity(event.srcElement),
      eventPhase: event.eventPhase, cancelBubble: event.cancelBubble,
      returnValue: event.returnValue, isTrusted: event.isTrusted,
      composedPath: event.composedPath().map(identity),
    }]);
  }
  function run(action) {
    const [kind, ...args] = action;
    switch (kind) {
      case "prevent": event.preventDefault(); break;
      case "stop": event.stopPropagation(); break;
      case "immediate": event.stopImmediatePropagation(); break;
      case "bubble": event.cancelBubble = args[0]; break;
      case "return": event.returnValue = args[0]; break;
      case "init": event.initEvent(...args); break;
      case "throw":
        steps.push(["throw"]);
        throw new Error("event-state listener fixture");
      case "recursive": {
        let error;
        try { other.dispatchEvent(event); } catch (caught) { error = caught; }
        if (!error) throw new Error("recursive-dispatch fixture unexpectedly succeeded");
        steps.push(["recursive", { name: error.name, code: error.code, message: error.message }]);
        checkpoint();
        return;
      }
      default: throw new Error(`Unknown action ${kind}`);
    }
    steps.push(action);
    checkpoint();
  }
  checkpoint();
  for (const action of definition.before) run(action);
  for (const listener of definition.listeners) {
    target.addEventListener(event.type, () => {
      steps.push(["enter", listener.passive]);
      checkpoint();
      try {
        for (const action of listener.actions) run(action);
        steps.push(["returned"]);
      } finally {
        steps.push(["leave"]);
      }
    }, { passive: listener.passive });
  }
  steps.push(["begin", 1]);
  const result = target.dispatchEvent(event);
  steps.push(["finish"], ["dispatchResult", result]);
  checkpoint();
  for (const action of definition.after) run(action);
  return { name: definition.name, init: definition.init, steps };
});
await new Promise(resolve => setImmediate(resolve));
process.removeListener("uncaughtException", captureError);
assert.deepEqual(listenerErrors, ["event-state listener fixture"]);
console.log(JSON.stringify({ node: process.version, cases }));
