// Test-only oracle for tests/markdown-test.bend: pi-mono's
// packages/tui/test/markdown.test.ts, run as upstream wrote it with its
// Markdown class replaced by a recording subclass. Every assertion of that
// file is about the lines Markdown renders (directly, or through the TUI
// and a virtual terminal), so the port records, under each test name, every
// Markdown the test creates: its constructor arguments, setText/invalidate
// calls and each render's width, hyperlink capability and lines, plus the
// calls of its transform option. tests/markdown-test.bend replays them and
// must render the same lines (and make the same transform calls).
//
// Theme and default-style functions are described by probing: each is a
// chalk style chain (chalk's reopening of nested closes and per-line
// wrapping) or a plain `open + text + close` wrapper; the description is
// checked against the function on probe strings.
//
//   bun tests/markdown_test_reference.ts OUT_DIR [PI_MONO]
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
import assert from "node:assert/strict";

const [outArgument, root = "/home/agent/code/pi-mono"] = process.argv.slice(2);
const out = resolve(outArgument);
mkdirSync(out, { recursive: true });
const testPath = `${root}/packages/tui/test/markdown.test.ts`;
assert.equal(createHash("sha256").update(readFileSync(testPath)).digest("hex"), "1060dbf84302c3984479b7a33ad4aaf21ae0616b8c02a45f066ba6e8f200f14d");
assert.equal(createHash("sha256").update(readFileSync(`${root}/packages/tui/src/components/markdown.ts`)).digest("hex"), "704c1c714a7ff6bdec55573ab38393726fa73a7b47cf4c1161ccc4f08530ac28");

// Chalk's application of a style chain (chalk 5 source/index.js applyStyle).
const closes: Record<string, string> = { "1": "22", "2": "22", "3": "23", "4": "24", "7": "27", "8": "28", "9": "29" };
const closeOf = (code: string) => closes[code] ?? (/^(3[0-7]|9[0-7]|38;)/.test(code) ? "39" : /^(4[0-7]|10[0-7]|48;)/.test(code) ? "49" : null);
function chalkApply(styles: [string, string][], text: string): string {
	if (!text) return "";
	const openAll = styles.map(([open]) => open).join("");
	const closeAll = styles.map(([, close]) => close).reverse().join("");
	if (text.includes("\x1b")) for (const [open, close] of [...styles].reverse()) text = text.split(close).join(close + open);
	if (text.includes("\n")) text = text.replace(/\r?\n/g, (lineBreak) => closeAll + lineBreak + openAll);
	return openAll + text + closeAll;
}
const probes = ["", "a", "a\nb", "c\r\nd", "x\x1b[39my", "x\x1b[22my\x1b[23mz\x1b[24m\x1b[29m\x1b[49m", "\x1b[0mq", "\x1b[1mbold\x1b[22m"];
function describeStyle(style: ((text: string) => string) | undefined): unknown {
	if (!style) return null;
	const [open, close] = style("\u0000").split("\u0000");
	const codes = [...open.matchAll(/\x1b\[([0-9;]*)m/g)].map((match) => match[1]);
	if (codes.length > 0 && codes.map((code) => `\x1b[${code}m`).join("") === open && codes.every((code) => closeOf(code))) {
		const styles = codes.map((code) => [`\x1b[${code}m`, `\x1b[${closeOf(code)}m`] as [string, string]);
		if (probes.every((probe) => chalkApply(styles, probe) === style(probe))) return { chalk: styles };
	}
	if (probes.every((probe) => open + probe + close === style(probe))) return { wrap: [open, close] };
	throw new Error(`undescribed style: ${JSON.stringify(style("\u0000"))}`);
}
const themeKeys = ["heading", "link", "linkUrl", "code", "codeBlock", "codeBlockBorder", "quote", "quoteBorder", "hr", "listBullet", "bold", "italic", "strikethrough", "underline"];
function describeTheme(theme: any) {
	assert.equal(theme.highlightCode, undefined);
	return { styles: themeKeys.map((key) => describeStyle(theme[key])), codeBlockIndent: theme.codeBlockIndent ?? null };
}
function describeDefault(style: any) {
	if (!style) return null;
	return { color: describeStyle(style.color), bgColor: describeStyle(style.bgColor), bold: !!style.bold, italic: !!style.italic, strikethrough: !!style.strikethrough, underline: !!style.underline };
}

const markdownModule = await import(`${root}/packages/tui/src/components/markdown.ts`);
const { getCapabilities } = await import(`${root}/packages/tui/src/terminal-image.ts`);
type Instance = { test: string; text: string; paddingX: number; paddingY: number; theme: unknown; style: unknown; options: unknown; events: unknown[]; calls: [string, number][] };
const instances: Instance[] = [];
let current = "";
class RecordingMarkdown extends markdownModule.Markdown {
	private record: Instance;
	constructor(text: string, paddingX: number, paddingY: number, theme: any, style?: any, options?: any) {
		const calls: [string, number][] = [];
		let transform = options?.transform;
		if (transform) {
			// The one transform upstream's tests use appends the width.
			const original = transform;
			transform = (source: string, width: number) => {
				const result = original(source, width);
				assert.equal(result, `${source} ${width}`);
				calls.push([source, width]);
				return result;
			};
		}
		super(text, paddingX, paddingY, theme, style, options && { ...options, transform });
		this.record = { test: current, text, paddingX, paddingY, theme: describeTheme(theme), style: describeDefault(style), options: { preserveOrderedListMarkers: !!options?.preserveOrderedListMarkers, preserveBackslashEscapes: !!options?.preserveBackslashEscapes, renderLatex: options?.renderLatex !== false, transform: !!options?.transform }, events: [], calls };
		instances.push(this.record);
	}
	setText(text: string) { this.record.events.push({ setText: text }); super.setText(text); }
	invalidate() { this.record.events.push({ invalidate: true }); super.invalidate(); }
	render(width: number) {
		const lines = super.render(width);
		this.record.events.push({ render: width, hyperlinks: !!getCapabilities().hyperlinks, lines: [...lines] });
		return lines;
	}
}

// The test file, run with the recording class and a sequential describe/it.
const tests: { name: string; body: () => unknown }[] = [];
const names: string[] = [];
const describe = (name: string, body: () => void) => { names.push(name); body(); names.pop(); };
const it = (name: string, body: () => unknown) => { tests.push({ name: [...names, name].join(" > "), body }); };
const afterEach = (_hook: () => void) => {};
(globalThis as any).__markdownTest = { describe, it, afterEach, Markdown: RecordingMarkdown };
let text = readFileSync(testPath, "utf8");
text = text
	.replace(/import \{ afterEach, describe, it \} from "node:test";/, "const { afterEach, describe, it } = (globalThis as any).__markdownTest;")
	.replace(/import \{ Markdown, type MarkdownTheme \} from "\.\.\/src\/components\/markdown\.ts";/, `import type { MarkdownTheme } from "${root}/packages/tui/src/components/markdown.ts";\nconst { Markdown } = (globalThis as any).__markdownTest;`)
	.replaceAll('from "../src/', `from "${root}/packages/tui/src/`)
	.replaceAll('from "./', `from "${root}/packages/tui/test/`)
	.replace('from "chalk";', `from "${root}/node_modules/chalk/source/index.js";`);
const copy = `${out}/markdown.test.recorded.ts`;
writeFileSync(copy, text);
await import(copy);
let passed = 0;
for (const test of tests) {
	current = test.name;
	await test.body();
	passed++;
}

const cases = instances.map(({ test, ...rest }) => JSON.stringify(rest));
writeFileSync(`${out}/cases.jsonl`, cases.join("\n") + "\n");
writeFileSync(`${out}/expected.jsonl`, instances.map((instance) => JSON.stringify({ renders: (instance.events as any[]).filter((event) => "render" in event).map((event) => event.lines), calls: instance.calls })).join("\n") + "\n");
writeFileSync(`${out}/labels.jsonl`, instances.map((instance) => JSON.stringify(instance.test)).join("\n") + "\n");
writeFileSync(`${out}/tests.json`, JSON.stringify(tests.map((test) => test.name)));
console.log(`${passed}/${tests.length} upstream tests pass on upstream; ${instances.length} Markdown instances recorded`);
