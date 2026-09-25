// Upstream tui suites replayed on the native TUI. tests/tui-virtual-terminal.bend
// renders a script with the native renderer; upstream's VirtualTerminal
// (xterm headless, from the pinned pi-mono checkout) receives its writes, and
// each case keeps its upstream suite, name and assertions. Test-only oracle:
// no production behavior comes from here.
//
// Usage: bun tests/tui_virtual_terminal.ts            (Bun lane)
//        TUI_RUNNER=build/tui-virtual-terminal bun tests/tui_virtual_terminal.ts
import assert from "node:assert";
import { spawnSync } from "node:child_process";
import path from "node:path";

const ROOT = path.resolve(import.meta.dir, "..");
const PI_MONO = process.env.PI_MONO ?? path.resolve(ROOT, "../pi-mono");
const { VirtualTerminal } = await import(`${PI_MONO}/packages/tui/test/virtual-terminal.ts`);
type Terminal = InstanceType<typeof VirtualTerminal>;

type Options = Record<string, unknown>;
type Op =
	| { op: "add"; lines: string[] }
	| { op: "set"; component: number; lines: string[] }
	| { op: "overlay"; lines: string[]; options?: Options }
	| { op: "clear" }
	| { op: "render"; width: number; height: number };

// Upstream writes percentages as "N%"; the fixture reads {"percent": N}.
function encodeOptions(options: Options | undefined): Options {
	const out: Options = {};
	for (const [key, value] of Object.entries(options ?? {})) {
		out[key] = typeof value === "string" && value.endsWith("%") ? { percent: Number(value.slice(0, -1)) } : value;
	}
	return out;
}

function frames(ops: Op[]): string[][] {
	const script = JSON.stringify(ops.map((o) => (o.op === "overlay" ? { ...o, options: encodeOptions(o.options) } : o)));
	const command = process.env.TUI_RUNNER
		? [path.resolve(ROOT, process.env.TUI_RUNNER), script]
		: [path.join(ROOT, "build/bend-native-toolchain/bend2/main.ts"), path.join(ROOT, "tests/tui-virtual-terminal.bend"), script];
	const result = spawnSync(command[0], command.slice(1), { encoding: "utf8", maxBuffer: 1 << 28 });
	if (result.status !== 0) throw new Error(`fixture failed (${result.status}): ${result.stderr}`);
	return result.stdout.split("\n").filter((line) => line.length > 0).map((line) => JSON.parse(line));
}

// Replays the script's frames into a fresh VirtualTerminal; `after(k)` runs
// the assertions that upstream makes after the k-th render.
async function replay(columns: number, rows: number, ops: Op[], after: (k: number, terminal: Terminal) => void) {
	const terminal = new VirtualTerminal(columns, rows);
	terminal.start(() => {}, () => {});
	for (const [k, writes] of frames(ops).entries()) {
		for (const data of writes) terminal.write(data);
		await terminal.flush();
		after(k, terminal);
	}
	terminal.stop();
}

function italicAt(terminal: Terminal, row: number, col: number): number {
	const xterm = (terminal as unknown as { xterm: import("@xterm/headless").Terminal }).xterm;
	const buffer = xterm.buffer.active;
	const line = buffer.getLine(buffer.viewportY + row);
	assert.ok(line, `Missing buffer line at row ${row}`);
	const cell = line.getCell(col);
	assert.ok(cell, `Missing cell at row ${row} col ${col}`);
	return cell.isItalic();
}

const cases: [string, string, () => Promise<void>][] = [];
const it = (suite: string, name: string, body: () => Promise<void>) => cases.push([suite, name, body]);

// tui-shrink.test.ts
it("TUI shrinking content", "clears all rendered lines when content shrinks to zero", () =>
	replay(40, 10, [
		{ op: "add", lines: ["first", "second", "third"] },
		{ op: "render", width: 40, height: 10 },
		{ op: "clear" },
		{ op: "render", width: 40, height: 10 },
	], (k, terminal) => {
		const viewport = terminal.getViewport();
		if (k === 0) {
			assert.ok(viewport.some((line: string) => line.includes("first")));
			assert.ok(viewport.some((line: string) => line.includes("second")));
			assert.ok(viewport.some((line: string) => line.includes("third")));
		} else {
			assert.ok(!viewport.some((line: string) => line.includes("first")), "first line should be cleared");
			assert.ok(!viewport.some((line: string) => line.includes("second")), "second line should be cleared");
			assert.ok(!viewport.some((line: string) => line.includes("third")), "third line should be cleared");
		}
	}));

// overlay-short-content.test.ts
it("TUI overlay with short content", "should render overlay when content is shorter than terminal height", () =>
	replay(80, 24, [
		{ op: "add", lines: ["Line 1", "Line 2", "Line 3"] },
		{ op: "overlay", lines: ["OVERLAY_TOP", "OVERLAY_MID", "OVERLAY_BOT"] },
		{ op: "render", width: 80, height: 24 },
	], (_, terminal) => {
		const viewport = terminal.getViewport();
		assert.ok(viewport.some((line: string) => line.includes("OVERLAY")), "Overlay should be visible when content is shorter than terminal");
	}));

// tui-overlay-style-leak.test.ts
const italicRow = `\x1b[3m${"X".repeat(20)}\x1b[23m`;
it("TUI overlay compositing", "should not leak styles when a trailing reset sits beyond the last visible column (no overlay)", () =>
	replay(20, 6, [
		{ op: "add", lines: [italicRow, "INPUT"] },
		{ op: "render", width: 20, height: 6 },
	], (_, terminal) => assert.strictEqual(italicAt(terminal, 1, 0), 0)));
it("TUI overlay compositing", "should not leak styles when overlay slicing drops trailing SGR resets", () =>
	replay(20, 6, [
		{ op: "add", lines: [italicRow, "INPUT"] },
		{ op: "overlay", lines: ["OVR"], options: { row: 0, col: 5, width: 3 } },
		{ op: "render", width: 20, height: 6 },
	], (_, terminal) => assert.strictEqual(italicAt(terminal, 1, 0), 0)));

const only = process.argv[2];
let failed = 0;
for (const [suite, name, body] of cases) {
	if (only !== undefined && !`${suite} › ${name}`.includes(only)) continue;
	try {
		await body();
		console.log(`ok   ${suite} › ${name}`);
	} catch (error) {
		failed += 1;
		console.log(`FAIL ${suite} › ${name}\n     ${(error as Error).message.split("\n").join("\n     ")}`);
	}
}
process.exit(failed === 0 ? 0 : 1);
