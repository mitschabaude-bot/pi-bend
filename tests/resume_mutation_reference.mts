import { UPSTREAM } from "./upstream_pin.mjs";
import { existsSync } from "node:fs";
const {SessionManager} = await import(UPSTREAM + "/packages/coding-agent/src/core/session-manager.ts");
const {SessionSelectorComponent} = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/components/session-selector.ts");
const {setKeybindings} = await import(UPSTREAM + "/packages/tui/src/keybindings.ts");
const {KeybindingsManager} = await import(UPSTREAM + "/packages/coding-agent/src/core/keybindings.ts");
const {initTheme} = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/theme/theme.ts");
const root = process.argv[2], directory = root + "/sessions";
const bindings = new KeybindingsManager();
setKeybindings(bindings);
initTheme("dark");
let currentCalls = 0, allCalls = 0;
const selector = new SessionSelectorComponent(
  (progress,signal) => {currentCalls++; return SessionManager.list(root + "/project",directory,progress,signal);},
  (progress,signal) => {allCalls++; return SessionManager.listAll(directory,progress,signal);},
  () => {throw new Error("mutation selected a session");}, () => {}, () => {}, () => {},
  {keybindings: bindings, renameSession: async (path,name) => {SessionManager.open(path,directory).appendSessionInfo(name);}},
);
selector.focused = true;
const wait = async (predicate) => {
  const deadline = Date.now() + 10000;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error("resume mutation did not settle");
    await new Promise(resolve => setTimeout(resolve,1));
  }
};
const ready = () => selector.mode === "list" && (selector.scope === "current" ? selector.currentSessions !== null && selector.currentLoad === null : selector.allSessions !== null && selector.allLoad === null);
const rows = infos => (infos ?? []).map(info => [info.path,info.name ?? ""]);
const emit = stage => console.log(JSON.stringify({stage,scope: selector.scope,current: rows(selector.currentSessions),all: rows(selector.allSessions),requested: [selector.currentSessions !== null || selector.currentLoad !== null,selector.allSessions !== null || selector.allLoad !== null]}));
await wait(ready); emit("current");
selector.handleInput("\t"); await wait(ready); emit("all");
selector.handleInput("\t"); selector.handleInput("\x12");
const target = selector.getSessionList().getSelectedSessionPath();
if (selector.mode !== "rename") throw new Error("rename did not open");
selector.renameInput.setValue("Renamed target"); selector.handleInput("\r");
await wait(() => currentCalls === 2 && ready()); emit("renamed-current");
selector.handleInput("\t"); await wait(ready); emit("renamed-all");
await selector.getSessionList().onDeleteSession(target);
await wait(() => allCalls === 3 && !existsSync(target) && ready()); emit("deleted-all");
selector.handleInput("\t"); await wait(ready); emit("deleted-current");
selector.header.setStatusMessage(null); selector.cancelLoads();
