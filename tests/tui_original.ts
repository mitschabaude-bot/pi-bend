// Executes original pinned tui test files (editor.test.ts,
// editor-history-keybindings.test.ts, mouse-components.test.ts), unchanged
// apart from import redirection, against native components through
// tests/tui-bridge.bend. Assertions, names and inputs are upstream's;
// tests/editor.md lists the adaptations and the tests that are still pending.
//
// Usage: bun tests/tui_original.ts [suite...]                  (Bun lane)
//        TUI_BRIDGE="build/tui-bridge --threads 4" bun tests/tui_original.ts
import { UPSTREAM } from "./upstream_pin.mjs";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { closeBridge } from "./tui_bridge.ts";
import { run } from "./original_harness.ts";

const ROOT = path.resolve(import.meta.dir, "..");
const TEST = path.join(UPSTREAM, "packages/tui/test");
const suites: Record<string, string> = {
	"editor.test.ts": "b25d663eda552a486aa35965441b6fae056414b2b5750ddec96b69faec72bdd6",
	"editor-history-keybindings.test.ts": "a055311e76a141062038a1a835fae1271108d29034fe0d0eec7521c6c79cb948",
	"mouse-components.test.ts": "2f24456f3d3a0cda99e6018e055f9522b64fa51d37315bd97b0cb6d2cb2a6e63",
};
const redirected: Record<string, string> = {
	"node:test": path.join(ROOT, "tests/original_harness.ts"),
	"../src/components/editor.ts": path.join(ROOT, "tests/tui_bridge.ts"),
	"../src/tui-main-screen.ts": path.join(ROOT, "tests/tui_bridge.ts"),
	"../src/tui.ts": path.join(ROOT, "tests/tui_bridge.ts"),
	"../src/utils.ts": path.join(ROOT, "tests/tui_bridge.ts"),
	"../src/autocomplete.ts": path.join(ROOT, "tests/tui_bridge.ts"),
	"../src/keybindings.ts": path.join(ROOT, "tests/tui_bridge.ts"),
	"../src/components/input.ts": path.join(ROOT, "tests/tui_bridge.ts"),
	"../src/components/select-list.ts": path.join(ROOT, "tests/tui_bridge.ts"),
	"../src/components/settings-list.ts": path.join(ROOT, "tests/tui_bridge.ts"),
	"../src/tui-alt-screen.ts": path.join(ROOT, "tests/tui_bridge.ts"),
	"./virtual-terminal.ts": path.join(ROOT, "tests/tui_bridge.ts"),
	"./test-themes.ts": path.join(TEST, "test-themes.ts"),
};
// Autocomplete cases need asynchronous providers and mocked timers, which a
// synchronous bridge cannot drive; they remain pending (tests/editor.md).
const pending: Record<string, string[]> = {
	"editor.test.ts": [
		"Editor component > Autocomplete > ",
		"Editor component > Undo > does not trigger autocomplete during single-line paste",
		"Editor component > Undo > undoes autocomplete",
	],
	"editor-history-keybindings.test.ts": [],
	// Alternate-screen dispatch through a virtual terminal is not bridged.
	"mouse-components.test.ts": [
		"mouse-aware components > keeps a delegating overlay focused when its nested input is clicked",
		"mouse-aware components > positions and focuses the multiline editor through alternate-screen dispatch",
		"mouse-aware components > selects and copies editor text on drag instead of moving the cursor",
	],
};

const out = path.join(ROOT, "build/original-tests");
mkdirSync(out, { recursive: true });
let failures = 0;
const selected = process.argv.slice(2);
for (const [file, digest] of Object.entries(suites)) {
	if (selected.length > 0 && !selected.includes(file)) continue;
	const source = readFileSync(path.join(TEST, file), "utf8");
	const actual = createHash("sha256").update(source).digest("hex");
	if (actual !== digest) throw new Error(`${file}: upstream hash ${actual} differs from the pinned ${digest}`);
	const rewritten = source.replace(/(\bfrom\s+|\bimport\s+)"([^"]+)"/g, (whole, keyword, specifier) => {
		if (specifier in redirected) return `${keyword}${JSON.stringify(redirected[specifier])}`;
		if (specifier.startsWith(".")) throw new Error(`${file}: unredirected import ${specifier}`);
		return whole;
	});
	const target = path.join(out, file);
	writeFileSync(target, rewritten);
	await import(target);
	const outcome = await run(pending[file]);
	for (const name of outcome.passed) console.log(`ok ${file}: ${name}`);
	for (const name of outcome.pending) console.log(`pending ${file}: ${name}`);
	for (const [name, error] of outcome.failed) console.log(`FAIL ${file}: ${name}\n  ${String(error instanceof Error ? error.message : error).replaceAll("\n", "\n  ")}`);
	console.log(`${file}: ${outcome.passed.length} passed, ${outcome.failed.length} failed, ${outcome.pending.length} pending`);
	failures += outcome.failed.length;
}
closeBridge();
process.exit(failures === 0 ? 0 : 1);
