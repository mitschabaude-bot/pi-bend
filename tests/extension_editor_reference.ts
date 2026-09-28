import { UPSTREAM } from "./upstream_pin.mjs";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { strict as assert } from "node:assert";

const path = "packages/coding-agent/src/modes/interactive/components/extension-editor.ts";
assert.equal(createHash("sha256").update(readFileSync(`${UPSTREAM}/${path}`)).digest("hex"), "d41f13dfaf73596643111fac10520b190998202627c6004eb6846d42ce9d37f1");
const { ExtensionEditorComponent } = await import(`${UPSTREAM}/${path}`);
const { KeybindingsManager, setKeybindings } = await import(`${UPSTREAM}/packages/tui/src/keybindings.ts`);
const { KEYBINDINGS } = await import(`${UPSTREAM}/packages/coding-agent/src/core/keybindings.ts`);
const { initTheme } = await import(`${UPSTREAM}/packages/coding-agent/src/modes/interactive/theme/theme.ts`);

initTheme("dark");
setKeybindings(new KeybindingsManager(KEYBINDINGS));
const ui = { requestRender() {}, terminal: { rows: 24 } };
const emit = (label: string, component: InstanceType<typeof ExtensionEditorComponent>, width: number) =>
  process.stdout.write(`${label}\x1e${component.render(width).join("\x1f")}\n`);
const editor = new ExtensionEditorComponent(ui as any, new KeybindingsManager(KEYBINDINGS), "Compose", "seed", () => {}, () => {}, { description: "A description" });
editor.focused = true;
emit("initial", editor, 32);
editor.handleInput("x");
emit("typed", editor, 32);
const empty = new ExtensionEditorComponent(ui as any, new KeybindingsManager(KEYBINDINGS), "Empty", "", () => {}, () => {});
empty.focused = true;
emit("empty", empty, 12);
