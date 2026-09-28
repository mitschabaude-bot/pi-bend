import { UPSTREAM } from "./upstream_pin.mjs";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { strict as assert } from "node:assert";

const path = "packages/coding-agent/src/modes/interactive/components/extension-input.ts";
assert.equal(createHash("sha256").update(readFileSync(`${UPSTREAM}/${path}`)).digest("hex"), "efd8f7c27b2a1f1a9215e0cca31a34b3d54db2783ade2914dfa1facf8e1945bd");
const { ExtensionInputComponent } = await import(`${UPSTREAM}/${path}`);
const { KeybindingsManager, setKeybindings } = await import(`${UPSTREAM}/packages/tui/src/keybindings.ts`);
const { KEYBINDINGS } = await import(`${UPSTREAM}/packages/coding-agent/src/core/keybindings.ts`);
const { initTheme } = await import(`${UPSTREAM}/packages/coding-agent/src/modes/interactive/theme/theme.ts`);

initTheme("dark");
setKeybindings(new KeybindingsManager(KEYBINDINGS));
const emit = (label: string, component: InstanceType<typeof ExtensionInputComponent>, width: number) =>
  process.stdout.write(`${label}\x1e${component.render(width).join("\x1f")}\n`);
const input = new ExtensionInputComponent("Enter value", undefined, () => {}, () => {}, { initialValue: "seed", description: "A description" });
input.focused = true;
emit("initial", input, 32);
input.handleInput("x");
emit("typed", input, 32);
const empty = new ExtensionInputComponent("Empty", undefined, () => {}, () => {});
empty.focused = true;
emit("empty", empty, 12);
