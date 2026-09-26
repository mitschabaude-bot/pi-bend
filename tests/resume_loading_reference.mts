import { UPSTREAM } from "./upstream_pin.mjs";
process.env.COLORTERM = "truecolor";
process.env.FORCE_COLOR = "3";
process.env.HOME = "/home/agent";
const RealDate = Date;
globalThis.Date = class extends RealDate {
  constructor(...args: any[]) { super(...(args.length ? args : [3600000])); }
  static now() { return 3600000; }
} as DateConstructor;
const {initTheme} = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/theme/theme.ts");
const {SessionSelectorComponent} = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/components/session-selector.ts");
const {setKeybindings} = await import(UPSTREAM + "/packages/tui/src/keybindings.ts");
const {KeybindingsManager} = await import(UPSTREAM + "/packages/coding-agent/src/core/keybindings.ts");
const bindings = new KeybindingsManager();
setKeybindings(bindings);
initTheme("dark");
const keys = {up: "\x1b[A", down: "\x1b[B", "page-up": "\x1b[5~", "page-down": "\x1b[6~", enter: "\r", escape: "\x1b", scope: "\t", sort: "\x13", named: "\x0e", path: "\x10", delete: "\x04", "delete-alias": "\x1b[127;5u", backspace: "\x7f", clear: "\x15"};
let input = "";
for await (const chunk of process.stdin) input += chunk;
const cases = JSON.parse(input);
const output = [];
const flush = () => new Promise(resolve => setImmediate(resolve));
const info = value => ({path: value.path, id: value.id, cwd: value.cwd ?? "", name: value.name ?? undefined, parentSessionPath: value.parentSessionPath ?? undefined, created: new Date(0), modified: new Date(value.modified ?? 0), messageCount: 1, firstMessage: value.firstMessage ?? "hello", allMessagesText: value.allMessagesText ?? "hello"});
for (const c of cases) {
  let action = "continue";
  const pending: Record<string, {progress: Function, resolve: Function}> = {};
  const loader = scope => (progress, signal) => new Promise(resolve => { pending[scope] = {progress, resolve}; });
  const selector = new SessionSelectorComponent(loader("current"), loader("all"), path => {action = "chosen:" + path;}, () => {action = "cancel";}, () => {action = "cancel";}, () => {}, {keybindings: bindings, renameSession: async () => {}});
  selector.focused = true;
  const list = selector.getSessionList();
  const snap = () => ({paths: list.filteredSessions.map(node => node.session.path), selected: list.getSelectedSessionPath() ?? null, query: list.searchInput.getValue(), action, deleting: list.confirmingDeletePath, status: selector.header.statusMessage?.message ?? null, lines: selector.render(c.width)});
  const result = [snap()];
  for (const step of c.actions) {
    if (step.kind === "key") selector.handleInput(keys[step.key] ?? step.key);
    else if (step.kind === "progress") pending[step.scope].progress(step.loaded, step.total, step.items.map(info));
    else if (step.kind === "complete") pending[step.scope].resolve(step.items.map(info));
    else throw new Error("unknown step");
    await flush();
    result.push(snap());
  }
  output.push(result);
  selector.cancelLoads();
}
await new Promise<void>(resolve => process.stdout.write(JSON.stringify(output), () => resolve()));
process.exit(0);
