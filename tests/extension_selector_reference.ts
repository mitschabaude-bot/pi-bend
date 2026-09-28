import { UPSTREAM } from "./upstream_pin.mjs";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { strict as assert } from "node:assert";

const path = "packages/coding-agent/src/modes/interactive/components/extension-selector.ts";
assert.equal(createHash("sha256").update(readFileSync(`${UPSTREAM}/${path}`)).digest("hex"), "d83767b09d73264eb0cb9af54b6f13e0e9c15a429a6dd7b9c8e7498e013b7704");
const { ExtensionSelectorComponent } = await import(`${UPSTREAM}/${path}`);
const { KeybindingsManager, setKeybindings } = await import(`${UPSTREAM}/packages/tui/src/keybindings.ts`);
const { KEYBINDINGS } = await import(`${UPSTREAM}/packages/coding-agent/src/core/keybindings.ts`);
const { initTheme } = await import(`${UPSTREAM}/packages/coding-agent/src/modes/interactive/theme/theme.ts`);

initTheme("dark");
setKeybindings(new KeybindingsManager(KEYBINDINGS));
const emit = (label: string, component: InstanceType<typeof ExtensionSelectorComponent>, width: number) =>
  process.stdout.write(`${label}\x1e${component.render(width).join("\x1f")}\n`);
const selector = new ExtensionSelectorComponent("Choose one", ["first", "second"], () => {}, () => {}, { description: "For this run" });
emit("initial", selector, 32);
selector.handleInput("j");
emit("down", selector, 32);
emit("down-narrow", selector, 12);
const empty = new ExtensionSelectorComponent("Empty", [], () => {}, () => {});
emit("empty", empty, 32);
