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
// A line, or `fill` repeated (render width - less) times between prefix and suffix.
type Line = string | { prefix?: string; fill: string; less?: number; suffix?: string };
type Report = { writes: string[]; widths: (number | null)[] };
type Op =
	| { op: "add"; lines: Line[] }
	| { op: "set"; component: number; lines: Line[] }
	| { op: "overlay"; lines: Line[]; options?: Options }
	| { op: "hide"; overlay: number }
	| { op: "hideTop" }
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

function frames(ops: Op[]): Report[] {
	const script = JSON.stringify(ops.map((o) => (o.op === "overlay" ? { ...o, options: encodeOptions(o.options) } : o)));
	const command = process.env.TUI_RUNNER
		? [path.resolve(ROOT, process.env.TUI_RUNNER), script]
		: [path.join(ROOT, "build/bend-native-toolchain/bend2/main.ts"), path.join(ROOT, "tests/tui-virtual-terminal.bend"), script];
	const result = spawnSync(command[0], command.slice(1), { encoding: "utf8", maxBuffer: 1 << 28 });
	if (result.status !== 0) throw new Error(`fixture failed (${result.status}): ${result.stderr}`);
	return result.stdout.split("\n").filter((line) => line.length > 0).map((line) => JSON.parse(line));
}

// Replays the script's frames into a fresh VirtualTerminal; `after(k)` runs
// the assertions that upstream makes after the k-th render. `widths[i]` is
// the width component i (in creation order) was last asked to render at.
async function replay(columns: number, rows: number, ops: Op[], after: (k: number, terminal: Terminal, widths: (number | null)[]) => void) {
	const terminal = new VirtualTerminal(columns, rows);
	terminal.start(() => {}, () => {});
	for (const [k, report] of frames(ops).entries()) {
		for (const data of report.writes) terminal.write(data);
		await terminal.flush();
		after(k, terminal, report.widths);
	}
	terminal.stop();
}

// Upstream's common shape: base content, overlays shown in order, one render.
const withOverlays = (columns: number, rows: number, base: Line[], overlays: [Line[], Options][], check: (viewport: string[], widths: (number | null)[]) => void) =>
	replay(columns, rows, [
		{ op: "add", lines: base },
		...overlays.map(([lines, options]): Op => ({ op: "overlay", lines, options })),
		{ op: "render", width: columns, height: rows },
	], (_, terminal, widths) => check(terminal.getViewport(), widths));

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

// overlay-options.test.ts ("TUI overlay options"). Components are numbered
// in creation order: the base content is 0, the first overlay 1.
const OPT = "TUI overlay options";
it(`${OPT} › width overflow protection`, "should truncate overlay lines that exceed declared width", () =>
	withOverlays(80, 24, [], [[["X".repeat(100)], { width: 20 }]], (viewport) => {
		for (const line of viewport) assert.ok(line !== undefined);
	}));
it(`${OPT} › width overflow protection`, "should handle overlay with complex ANSI sequences without crashing", () => {
	const complexLine = "\x1b[48;2;40;50;40m \x1b[38;2;128;128;128mSome styled content\x1b[39m\x1b[49m" + "\x1b]8;;http://example.com\x07link\x1b]8;;\x07" + " more content ".repeat(10);
	return withOverlays(80, 24, [], [[[complexLine, complexLine, complexLine], { width: 60 }]], (viewport) => assert.ok(viewport.length > 0));
});
it(`${OPT} › width overflow protection`, "should handle overlay composited on styled base content", () => {
	const styled: Line = { prefix: "\x1b[1m\x1b[38;2;255;0;0m", fill: "X", suffix: "\x1b[0m" };
	return withOverlays(80, 24, [styled, styled, styled], [[["OVERLAY"], { width: 20, anchor: "center" }]], (viewport) =>
		assert.ok(viewport.some((line) => line?.includes("OVERLAY")), "Overlay should be visible"));
});
it(`${OPT} › width overflow protection`, "should handle wide characters at overlay boundary", () =>
	withOverlays(80, 24, [], [[["中文日本語한글テスト漢字"], { width: 15 }]], (viewport) => assert.ok(viewport.length > 0)));
it(`${OPT} › width overflow protection`, "should handle overlay positioned at terminal edge", () =>
	withOverlays(80, 24, [], [[["X".repeat(50)], { col: 60, width: 20 }]], (viewport) => assert.ok(viewport.length > 0)));
it(`${OPT} › width overflow protection`, "should handle overlay on base content with OSC sequences", () => {
	const link = "\x1b]8;;file:///path/to/file.ts\x07file.ts\x1b]8;;\x07";
	const line: Line = { prefix: `See ${link} for details `, fill: "X", less: 30 };
	return withOverlays(80, 24, [line, line, line], [[["OVERLAY-TEXT"], { anchor: "center", width: 20 }]], (viewport) => assert.ok(viewport.length > 0));
});
it(`${OPT} › width percentage`, "should render overlay at percentage of terminal width", () =>
	withOverlays(100, 24, [], [[["test"], { width: "50%" }]], (_, widths) => assert.strictEqual(widths[1], 50)));
it(`${OPT} › width percentage`, "should respect minWidth when widthPercent results in smaller width", () =>
	withOverlays(100, 24, [], [[["test"], { width: "10%", minWidth: 30 }]], (_, widths) => assert.strictEqual(widths[1], 30)));
it(`${OPT} › anchor positioning`, "should position overlay at top-left", () =>
	withOverlays(80, 24, [], [[["TOP-LEFT"], { anchor: "top-left", width: 10 }]], (viewport) =>
		assert.ok(viewport[0]?.startsWith("TOP-LEFT"), `Expected TOP-LEFT at start, got: ${viewport[0]}`)));
it(`${OPT} › anchor positioning`, "should position overlay at bottom-right", () =>
	withOverlays(80, 24, [], [[["BTM-RIGHT"], { anchor: "bottom-right", width: 10 }]], (viewport) => {
		const lastRow = viewport[23];
		assert.ok(lastRow?.includes("BTM-RIGHT"), `Expected BTM-RIGHT on last row, got: ${lastRow}`);
		assert.ok(lastRow?.trimEnd().endsWith("BTM-RIGHT"), `Expected BTM-RIGHT at end, got: ${lastRow}`);
	}));
it(`${OPT} › anchor positioning`, "should position overlay at top-center", () =>
	withOverlays(80, 24, [], [[["CENTERED"], { anchor: "top-center", width: 10 }]], (viewport) => {
		const firstRow = viewport[0];
		assert.ok(firstRow?.includes("CENTERED"), `Expected CENTERED on first row, got: ${firstRow}`);
		const colIndex = firstRow?.indexOf("CENTERED") ?? -1;
		assert.ok(colIndex >= 30 && colIndex <= 40, `Expected centered, got col ${colIndex}`);
	}));
// Adaptation: native overlay margins are Nat, so negative margins are clamped
// where options become an OverlayGeometry (here, the fixture's decoding);
// upstream clamps inside layout. The assertion is upstream's.
it(`${OPT} › margin`, "should clamp negative margins to zero", () =>
	withOverlays(80, 24, [], [[["NEG-MARGIN"], { anchor: "top-left", width: 12, margin: { top: -5, left: -10, right: 0, bottom: 0 } }]], (viewport) =>
		assert.ok(viewport[0]?.startsWith("NEG-MARGIN"), `Expected NEG-MARGIN at start of row 0, got: ${viewport[0]}`)));
it(`${OPT} › margin`, "should respect margin as number", () =>
	withOverlays(80, 24, [], [[["MARGIN"], { anchor: "top-left", width: 10, margin: 5 }]], (viewport) => {
		assert.ok(!viewport[0]?.includes("MARGIN"), "Should not be on row 0");
		assert.ok(!viewport[4]?.includes("MARGIN"), "Should not be on row 4");
		assert.ok(viewport[5]?.includes("MARGIN"), `Expected MARGIN on row 5, got: ${viewport[5]}`);
		const colIndex = viewport[5]?.indexOf("MARGIN") ?? -1;
		assert.strictEqual(colIndex, 5, `Expected col 5, got ${colIndex}`);
	}));
it(`${OPT} › margin`, "should respect margin object", () =>
	withOverlays(80, 24, [], [[["MARGIN"], { anchor: "top-left", width: 10, margin: { top: 2, left: 3, right: 0, bottom: 0 } }]], (viewport) => {
		assert.ok(viewport[2]?.includes("MARGIN"), `Expected MARGIN on row 2, got: ${viewport[2]}`);
		const colIndex = viewport[2]?.indexOf("MARGIN") ?? -1;
		assert.strictEqual(colIndex, 3, `Expected col 3, got ${colIndex}`);
	}));
it(`${OPT} › offset`, "should apply offsetX and offsetY from anchor position", () =>
	withOverlays(80, 24, [], [[["OFFSET"], { anchor: "top-left", width: 10, offsetX: 10, offsetY: 5 }]], (viewport) => {
		assert.ok(viewport[5]?.includes("OFFSET"), `Expected OFFSET on row 5, got: ${viewport[5]}`);
		const colIndex = viewport[5]?.indexOf("OFFSET") ?? -1;
		assert.strictEqual(colIndex, 10, `Expected col 10, got ${colIndex}`);
	}));
it(`${OPT} › percentage positioning`, "should position with rowPercent and colPercent", () =>
	withOverlays(80, 24, [], [[["PCT"], { width: 10, row: "50%", col: "50%" }]], (viewport) => {
		let foundRow = -1;
		for (let i = 0; i < viewport.length; i++) {
			if (viewport[i]?.includes("PCT")) {
				foundRow = i;
				break;
			}
		}
		assert.ok(foundRow >= 10 && foundRow <= 13, `Expected centered row, got ${foundRow}`);
	}));
it(`${OPT} › percentage positioning`, "rowPercent 0 should position at top", () =>
	withOverlays(80, 24, [], [[["TOP"], { width: 10, row: "0%" }]], (viewport) =>
		assert.ok(viewport[0]?.includes("TOP"), `Expected TOP on row 0, got: ${viewport[0]}`)));
it(`${OPT} › percentage positioning`, "rowPercent 100 should position at bottom", () =>
	withOverlays(80, 24, [], [[["BOTTOM"], { width: 10, row: "100%" }]], (viewport) =>
		assert.ok(viewport[23]?.includes("BOTTOM"), `Expected BOTTOM on last row, got: ${viewport[23]}`)));
it(`${OPT} › maxHeight`, "should truncate overlay to maxHeight", () =>
	withOverlays(80, 24, [], [[["Line 1", "Line 2", "Line 3", "Line 4", "Line 5"], { maxHeight: 3 }]], (viewport) => {
		const content = viewport.join("\n");
		assert.ok(content.includes("Line 1"), "Should include Line 1");
		assert.ok(content.includes("Line 2"), "Should include Line 2");
		assert.ok(content.includes("Line 3"), "Should include Line 3");
		assert.ok(!content.includes("Line 4"), "Should NOT include Line 4");
		assert.ok(!content.includes("Line 5"), "Should NOT include Line 5");
	}));
it(`${OPT} › maxHeight`, "should truncate overlay to maxHeightPercent", () =>
	withOverlays(80, 10, [], [[["L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "L10"], { maxHeight: "50%" }]], (viewport) => {
		const content = viewport.join("\n");
		assert.ok(content.includes("L1"), "Should include L1");
		assert.ok(content.includes("L5"), "Should include L5");
		assert.ok(!content.includes("L6"), "Should NOT include L6");
	}));
it(`${OPT} › absolute positioning`, "row and col should override anchor", () =>
	withOverlays(80, 24, [], [[["ABSOLUTE"], { anchor: "bottom-right", row: 3, col: 5, width: 10 }]], (viewport) => {
		assert.ok(viewport[3]?.includes("ABSOLUTE"), `Expected ABSOLUTE on row 3, got: ${viewport[3]}`);
		const colIndex = viewport[3]?.indexOf("ABSOLUTE") ?? -1;
		assert.strictEqual(colIndex, 5, `Expected col 5, got ${colIndex}`);
	}));
it(`${OPT} › stacked overlays`, "should render multiple overlays with later ones on top", () =>
	withOverlays(80, 24, [], [[["FIRST-OVERLAY"], { anchor: "top-left", width: 20 }], [["SECOND"], { anchor: "top-left", width: 10 }]], (viewport) =>
		assert.ok(viewport[0]?.includes("SECOND"), `Expected SECOND on row 0, got: ${viewport[0]}`)));
it(`${OPT} › stacked overlays`, "should handle overlays at different positions without interference", () =>
	withOverlays(80, 24, [], [[["TOP-LEFT"], { anchor: "top-left", width: 15 }], [["BTM-RIGHT"], { anchor: "bottom-right", width: 15 }]], (viewport) => {
		assert.ok(viewport[0]?.includes("TOP-LEFT"), `Expected TOP-LEFT on row 0, got: ${viewport[0]}`);
		assert.ok(viewport[23]?.includes("BTM-RIGHT"), `Expected BTM-RIGHT on row 23, got: ${viewport[23]}`);
	}));
it(`${OPT} › stacked overlays`, "should properly hide overlays in stack order", () =>
	replay(80, 24, [
		{ op: "add", lines: [] },
		{ op: "overlay", lines: ["FIRST"], options: { anchor: "top-left", width: 10 } },
		{ op: "overlay", lines: ["SECOND"], options: { anchor: "top-left", width: 10 } },
		{ op: "render", width: 80, height: 24 },
		{ op: "hideTop" },
		{ op: "render", width: 80, height: 24 },
	], (k, terminal) => {
		const viewport = terminal.getViewport();
		if (k === 0) assert.ok(viewport[0]?.includes("SECOND"), "SECOND should be visible initially");
		else assert.ok(viewport[0]?.includes("FIRST"), "FIRST should be visible after hiding SECOND");
	}));

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
