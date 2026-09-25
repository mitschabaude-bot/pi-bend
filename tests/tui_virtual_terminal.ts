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
// Per component (numbered in creation order): the width it was last asked to
// render at, the input it received and its `focused` flag; per overlay shown,
// OverlayHandle.isFocused(). A render adds its writes and tui.fullRedraws.
type ComponentState = { width: number | null; inputs: string[]; focused: boolean };
type State = { components: ComponentState[]; focused: boolean[] };
type Report = State & { writes: string[]; redraws: number; widths: (number | null)[] };
// A new component is {lines, focusable?, on?}: `on` maps input data to the
// operations its handleInput performs. "add" and "overlay" take a new one or
// {component: i}.
type Spec = { lines?: Line[]; focusable?: boolean; on?: Record<string, Op[]> };
type Op =
	| ({ op: "component" } & Spec)
	| ({ op: "add"; component?: number } & Spec)
	| { op: "set"; component: number; lines: Line[] }
	| ({ op: "overlay"; component?: number; options?: Options } & Spec)
	| { op: "hide"; overlay: number }
	| { op: "focus"; overlay: number }
	| { op: "unfocus"; overlay: number; target?: number | null }
	| { op: "setHidden"; overlay: number; hidden: boolean }
	| { op: "visible"; overlay: number; visible: boolean }
	| { op: "hideTop" }
	| { op: "setFocus"; component: number | null }
	| { op: "input"; data: string }
	| { op: "clear" }
	| { op: "clearOnShrink" }
	| { op: "check" }
	| { op: "render"; width: number; height: number; termux?: boolean };

// Upstream writes percentages as "N%"; the fixture reads {"percent": N}.
function encodeOptions(options: Options | undefined): Options {
	const out: Options = {};
	for (const [key, value] of Object.entries(options ?? {})) {
		out[key] = typeof value === "string" && value.endsWith("%") ? { percent: Number(value.slice(0, -1)) } : value;
	}
	return out;
}

const encode = (o: Op): Op => {
	const on = "on" in o && o.on ? { on: Object.fromEntries(Object.entries(o.on).map(([data, ops]) => [data, ops.map(encode)])) } : {};
	return o.op === "overlay" ? { ...o, ...on, options: encodeOptions(o.options) } : { ...o, ...on };
};

// The Bun lane compiles the fixture to JavaScript once per run.
let runner = process.env.TUI_RUNNER ? [path.resolve(ROOT, process.env.TUI_RUNNER)] : undefined;
function fixture(): string[] {
	if (runner) return runner;
	const out = path.join(ROOT, "build/tui-virtual-terminal.js");
	const built = spawnSync(path.join(ROOT, "build/bend-native-toolchain/bend2/main.ts"), [path.join(ROOT, "tests/tui-virtual-terminal.bend"), "-o", out], { encoding: "utf8" });
	if (built.status !== 0) throw new Error(`fixture build failed: ${built.stdout}${built.stderr}`);
	runner = [process.execPath, out];
	return runner;
}

function frames(ops: Op[]): Report[] {
	const [command, ...args] = fixture();
	const result = spawnSync(command, [...args, JSON.stringify(ops.map(encode))], { encoding: "utf8", maxBuffer: 1 << 28 });
	if (result.status !== 0) throw new Error(`fixture failed (${result.status}): ${result.stderr}`);
	return result.stdout
		.split("\n")
		.filter((line) => line.length > 0)
		.map((line) => {
			const report = JSON.parse(line);
			return { writes: [], redraws: 0, ...report, widths: report.components.map((c: ComponentState) => c.width) };
		});
}

// Replays the script's frames into a fresh VirtualTerminal, resized first
// when a render's size differs, as upstream resizes before the TUI renders;
// `after(k)` runs the assertions that upstream makes after the k-th render or
// check. In a report, `widths[i]` is the width component i (in creation
// order) was last asked to render at, and `redraws` upstream's tui.fullRedraws.
async function replay(columns: number, rows: number, ops: Op[], after: (k: number, terminal: Terminal, report: Report) => void) {
	const terminal = new VirtualTerminal(columns, rows);
	terminal.start(() => {}, () => {});
	const points = ops.filter((o): o is Extract<Op, { op: "render" | "check" }> => o.op === "render" || o.op === "check");
	let size = [columns, rows];
	for (const [k, report] of frames(ops).entries()) {
		const point = points[k];
		if (point.op === "check") {
			after(k, terminal, report);
			continue;
		}
		const { width, height } = point;
		if (width !== size[0] || height !== size[1]) {
			terminal.resize(width, height);
			size = [width, height];
		}
		for (const data of report.writes) terminal.write(data);
		await terminal.flush();
		after(k, terminal, report);
	}
	terminal.stop();
}

// Upstream's common shape: base content, overlays shown in order, one render.
const withOverlays = (columns: number, rows: number, base: Line[], overlays: [Line[], Options][], check: (viewport: string[], widths: (number | null)[]) => void) =>
	replay(columns, rows, [
		{ op: "add", lines: base },
		...overlays.map(([lines, options]): Op => ({ op: "overlay", lines, options })),
		{ op: "render", width: columns, height: rows },
	], (_, terminal, report) => check(terminal.getViewport(), report.widths));

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

// tui-render.test.ts: resize handling, content shrinkage and differential
// rendering. `lines(k)` renders component 0's lines after a change, as
// upstream sets component.lines and requests a render.
const RENDER = (columns: number, rows: number, extra: Partial<Extract<Op, { op: "render" }>> = {}): Op => ({ op: "render", width: columns, height: rows, ...extra });
const set = (lines: Line[], component = 0): Op => ({ op: "set", component, lines });
const numbered = (count: number, prefix = "Line ") => Array.from({ length: count }, (_, i) => `${prefix}${i}`);
it("TUI resize handling", "triggers full re-render when terminal height changes", () => {
	let initialRedraws = 0;
	return replay(40, 10, [{ op: "add", lines: ["Line 0", "Line 1", "Line 2"] }, RENDER(40, 10), RENDER(40, 15)], (k, terminal, report) => {
		if (k === 0) initialRedraws = report.redraws;
		else {
			assert.ok(report.redraws > initialRedraws, "Height change should trigger full redraw");
			assert.ok(terminal.getViewport()[0]?.includes("Line 0"), "Content preserved after height change");
		}
	});
});
it("TUI resize handling", "skips full re-render on height changes in Termux", () => {
	let initialRedraws = 0;
	let writes = "";
	const termux = { termux: true };
	return replay(40, 10, [{ op: "add", lines: numbered(20) }, RENDER(40, 10, termux), ...[15, 8, 14, 11].map((h) => RENDER(40, h, termux))], (k, terminal, report) => {
		if (k === 0) initialRedraws = report.redraws;
		else writes += report.writes.join("");
		if (k === 4) {
			assert.strictEqual(report.redraws, initialRedraws, "Height change should not trigger full redraw");
			assert.ok(!writes.includes("\x1b[2J"), "Height change should not clear the screen");
			assert.ok(!writes.includes("\x1b[3J"), "Height change should not clear scrollback");
			assert.ok(terminal.getViewport().join("\n").includes("Line 19"), "Latest content remains visible after resize");
		}
	});
});
it("TUI resize handling", "triggers full re-render when terminal width changes", () => {
	let initialRedraws = 0;
	return replay(40, 10, [{ op: "add", lines: ["Line 0", "Line 1", "Line 2"] }, RENDER(40, 10), RENDER(60, 10)], (k, _, report) => {
		if (k === 0) initialRedraws = report.redraws;
		else assert.ok(report.redraws > initialRedraws, "Width change should trigger full redraw");
	});
});
it("TUI content shrinkage", "clears empty rows when content shrinks significantly", () => {
	let initialRedraws = 0;
	return replay(40, 10, [{ op: "clearOnShrink" }, { op: "add", lines: numbered(6) }, RENDER(40, 10), set(["Line 0", "Line 1"]), RENDER(40, 10)], (k, terminal, report) => {
		if (k === 0) return void (initialRedraws = report.redraws);
		assert.ok(report.redraws > initialRedraws, "Content shrinkage should trigger full redraw");
		const viewport = terminal.getViewport();
		assert.ok(viewport[0]?.includes("Line 0"), "First line preserved");
		assert.ok(viewport[1]?.includes("Line 1"), "Second line preserved");
		assert.strictEqual(viewport[2]?.trim(), "", "Line 2 should be cleared");
		assert.strictEqual(viewport[3]?.trim(), "", "Line 3 should be cleared");
	});
});
it("TUI content shrinkage", "handles shrink to single line", () =>
	replay(40, 10, [{ op: "clearOnShrink" }, { op: "add", lines: numbered(4) }, RENDER(40, 10), set(["Only line"]), RENDER(40, 10)], (k, terminal) => {
		if (k === 0) return;
		const viewport = terminal.getViewport();
		assert.ok(viewport[0]?.includes("Only line"), "Single line rendered");
		assert.strictEqual(viewport[1]?.trim(), "", "Line 1 should be cleared");
	}));
it("TUI content shrinkage", "handles shrink to empty", () =>
	replay(40, 10, [{ op: "clearOnShrink" }, { op: "add", lines: numbered(3) }, RENDER(40, 10), set([]), RENDER(40, 10)], (k, terminal) => {
		if (k === 0) return;
		const viewport = terminal.getViewport();
		assert.strictEqual(viewport[0]?.trim(), "", "Line 0 should be cleared");
		assert.strictEqual(viewport[1]?.trim(), "", "Line 1 should be cleared");
	}));
it("TUI differential rendering", "tracks cursor correctly when content shrinks with unchanged remaining lines", () =>
	replay(40, 10, [{ op: "add", lines: numbered(5) }, RENDER(40, 10), set(numbered(3)), RENDER(40, 10), set(["Line 0", "CHANGED", "Line 2"]), RENDER(40, 10)], (k, terminal) => {
		if (k !== 2) return;
		const viewport = terminal.getViewport();
		assert.ok(viewport[1]?.includes("CHANGED"), `Expected "CHANGED" on line 1, got: ${viewport[1]}`);
	}));
const spinnerFrames = ["|", "/", "-", "\\"];
it("TUI differential rendering", "renders correctly when only a middle line changes (spinner case)", () =>
	replay(40, 10, [{ op: "add", lines: ["Header", "Working...", "Footer"] }, RENDER(40, 10), ...spinnerFrames.flatMap((f) => [set(["Header", `Working ${f}`, "Footer"]), RENDER(40, 10)])], (k, terminal) => {
		if (k === 0) return;
		const frame = spinnerFrames[k - 1];
		const viewport = terminal.getViewport();
		assert.ok(viewport[0]?.includes("Header"), `Header preserved: ${viewport[0]}`);
		assert.ok(viewport[1]?.includes(`Working ${frame}`), `Spinner updated: ${viewport[1]}`);
		assert.ok(viewport[2]?.includes("Footer"), `Footer preserved: ${viewport[2]}`);
	}));
it("TUI differential rendering", "resets styles after each rendered line", () =>
	replay(20, 6, [{ op: "add", lines: ["\x1b[3mItalic", "Plain"] }, RENDER(20, 6)], (_, terminal) => assert.strictEqual(italicAt(terminal, 1, 0), 0)));
it("TUI differential rendering", "renders correctly when first line changes but rest stays same", () =>
	replay(40, 10, [{ op: "add", lines: numbered(4) }, RENDER(40, 10), set(["CHANGED", "Line 1", "Line 2", "Line 3"]), RENDER(40, 10)], (k, terminal) => {
		if (k === 0) return;
		const viewport = terminal.getViewport();
		assert.ok(viewport[0]?.includes("CHANGED"), `First line changed: ${viewport[0]}`);
		assert.ok(viewport[1]?.includes("Line 1"), `Line 1 preserved: ${viewport[1]}`);
		assert.ok(viewport[2]?.includes("Line 2"), `Line 2 preserved: ${viewport[2]}`);
		assert.ok(viewport[3]?.includes("Line 3"), `Line 3 preserved: ${viewport[3]}`);
	}));
it("TUI differential rendering", "renders correctly when last line changes but rest stays same", () =>
	replay(40, 10, [{ op: "add", lines: numbered(4) }, RENDER(40, 10), set(["Line 0", "Line 1", "Line 2", "CHANGED"]), RENDER(40, 10)], (k, terminal) => {
		if (k === 0) return;
		const viewport = terminal.getViewport();
		assert.ok(viewport[0]?.includes("Line 0"), `Line 0 preserved: ${viewport[0]}`);
		assert.ok(viewport[1]?.includes("Line 1"), `Line 1 preserved: ${viewport[1]}`);
		assert.ok(viewport[2]?.includes("Line 2"), `Line 2 preserved: ${viewport[2]}`);
		assert.ok(viewport[3]?.includes("CHANGED"), `Last line changed: ${viewport[3]}`);
	}));
it("TUI differential rendering", "renders correctly when multiple non-adjacent lines change", () =>
	replay(40, 10, [{ op: "add", lines: numbered(5) }, RENDER(40, 10), set(["Line 0", "CHANGED 1", "Line 2", "CHANGED 3", "Line 4"]), RENDER(40, 10)], (k, terminal) => {
		if (k === 0) return;
		const viewport = terminal.getViewport();
		assert.ok(viewport[0]?.includes("Line 0"), `Line 0 preserved: ${viewport[0]}`);
		assert.ok(viewport[1]?.includes("CHANGED 1"), `Line 1 changed: ${viewport[1]}`);
		assert.ok(viewport[2]?.includes("Line 2"), `Line 2 preserved: ${viewport[2]}`);
		assert.ok(viewport[3]?.includes("CHANGED 3"), `Line 3 changed: ${viewport[3]}`);
		assert.ok(viewport[4]?.includes("Line 4"), `Line 4 preserved: ${viewport[4]}`);
	}));
it("TUI differential rendering", "handles transition from content to empty and back to content", () =>
	replay(40, 10, [{ op: "add", lines: numbered(3) }, RENDER(40, 10), set([]), RENDER(40, 10), set(["New Line 0", "New Line 1"]), RENDER(40, 10)], (k, terminal) => {
		const viewport = terminal.getViewport();
		if (k === 0) assert.ok(viewport[0]?.includes("Line 0"), "Initial content rendered");
		if (k === 2) {
			assert.ok(viewport[0]?.includes("New Line 0"), `New content rendered: ${viewport[0]}`);
			assert.ok(viewport[1]?.includes("New Line 1"), `New content line 1: ${viewport[1]}`);
		}
	}));
it("TUI differential rendering", "full re-renders when deleted lines move the viewport upward", () => {
	let initialRedraws = 0;
	return replay(20, 5, [{ op: "add", lines: numbered(12) }, RENDER(20, 5), set(numbered(7)), RENDER(20, 5)], (k, terminal, report) => {
		if (k === 0) return void (initialRedraws = report.redraws);
		assert.ok(report.redraws > initialRedraws, "Shrink should trigger a full redraw");
		assert.deepStrictEqual(terminal.getViewport(), ["Line 2", "Line 3", "Line 4", "Line 5", "Line 6"]);
	});
});
it("TUI differential rendering", "appends after a shrink without another full redraw once the viewport is reset", () => {
	let initialRedraws = 0;
	let redrawsAfterShrink = 0;
	return replay(20, 5, [{ op: "add", lines: numbered(8) }, RENDER(20, 5), set(["Line 0", "Line 1"]), RENDER(20, 5), set(["Line 0", "Line 1", "Line 2"]), RENDER(20, 5)], (k, terminal, report) => {
		if (k === 0) initialRedraws = report.redraws;
		if (k === 1) {
			assert.ok(report.redraws > initialRedraws, "Shrink should reset the viewport with a full redraw");
			redrawsAfterShrink = report.redraws;
		}
		if (k === 2) {
			assert.strictEqual(report.redraws, redrawsAfterShrink, "Append should stay on the differential path");
			assert.deepStrictEqual(terminal.getViewport(), ["Line 0", "Line 1", "Line 2", "", ""]);
		}
	});
});
it("TUI differential rendering", "clears stale content when maxLinesRendered was inflated by a transient component", () => {
	const editorLines = ["Editor 0", "Editor 1", "Editor 2"];
	let redrawsBeforeSwitch = 0;
	return replay(40, 10, [
		{ op: "add", lines: numbered(15, "Chat ") }, { op: "add", lines: editorLines }, RENDER(40, 10),
		set(numbered(8, "Selector "), 1), RENDER(40, 10),
		set(editorLines, 1), RENDER(40, 10),
		set(numbered(12, "Chat "), 0), RENDER(40, 10),
	], (k, terminal, report) => {
		if (k === 2) redrawsBeforeSwitch = report.redraws;
		if (k !== 3) return;
		assert.ok(report.redraws > redrawsBeforeSwitch, "Branch switch should trigger a full redraw");
		const viewport = terminal.getViewport();
		for (let i = 0; i < 10; i++) {
			const line = viewport[i] ?? "";
			assert.ok(!line.includes("Chat 12"), `Stale "Chat 12" at viewport row ${i}`);
			assert.ok(!line.includes("Chat 13"), `Stale "Chat 13" at viewport row ${i}`);
			assert.ok(!line.includes("Chat 14"), `Stale "Chat 14" at viewport row ${i}`);
		}
		assert.deepStrictEqual(viewport, ["Chat 5", "Chat 6", "Chat 7", "Chat 8", "Chat 9", "Chat 10", "Chat 11", "Editor 0", "Editor 1", "Editor 2"]);
	});
});

// overlay-non-capturing.test.ts. A Session writes upstream's TUI calls as
// fixture operations. Its component and handle objects read the report of the
// render or check whose assertions are running, so the assertions keep
// upstream's form (`editor.focused`, `editor.inputs`, `handle.isFocused()`).
// `renderAndFlush(check)` stands for upstream's renderAndFlush followed by
// its assertions; `check(assertions)` for assertions made without a render.
class Comp {
	constructor(private session: Session, readonly id: number, readonly spec: Extract<Op, { op: "component" }>) {}
	get focused() {
		return this.session.state().components[this.id].focused;
	}
	get inputs() {
		return this.session.state().components[this.id].inputs;
	}
}
class Handle {
	constructor(private session: Session, readonly index: number) {}
	hide() {
		this.session.push({ op: "hide", overlay: this.index });
	}
	focus() {
		this.session.push({ op: "focus", overlay: this.index });
	}
	unfocus(options?: { target: Comp | null }) {
		this.session.push({ op: "unfocus", overlay: this.index, ...(options ? { target: options.target?.id ?? null } : {}) });
	}
	setHidden(hidden: boolean) {
		this.session.push({ op: "setHidden", overlay: this.index, hidden });
	}
	// The overlay's `visible` option returns a variable; this assigns it.
	setVisible(visible: boolean) {
		this.session.push({ op: "visible", overlay: this.index, visible });
	}
	isFocused() {
		return this.session.state().focused[this.index];
	}
}
class Session {
	private ops: Op[] = [];
	private target = this.ops;
	private components = 0;
	private overlays = 0;
	private checks: (() => void)[] = [];
	private report?: Report;
	private screen?: Terminal;
	constructor(readonly columns = 80, readonly rows = 24) {}
	push(op: Op) {
		this.target.push(op);
	}
	state(): Report {
		assert.ok(this.report, "no report yet");
		return this.report;
	}
	viewport(): string[] {
		assert.ok(this.screen, "no terminal yet");
		return this.screen.getViewport();
	}
	private make(spec: Spec): Comp {
		const op = { op: "component" as const, ...spec };
		this.push(op);
		return new Comp(this, this.components++, op);
	}
	// upstream FocusableOverlay
	focusable(lines: string[]) {
		return this.make({ lines, focusable: true });
	}
	// upstream StaticOverlay; EmptyContent is plain([])
	plain(lines: string[]) {
		return this.make({ lines });
	}
	// Replaces `component.handleInput` for `data`: the input is still
	// recorded, then the calls `body` makes run.
	onInput(component: Comp, data: string, body: () => void) {
		const outer = this.target;
		this.target = [];
		body();
		component.spec.on = { ...component.spec.on, [data]: this.target };
		this.target = outer;
	}
	addChild(component: Comp) {
		this.push({ op: "add", component: component.id });
	}
	clear() {
		this.push({ op: "clear" });
	}
	setFocus(component: Comp | null) {
		this.push({ op: "setFocus", component: component?.id ?? null });
	}
	showOverlay(component: Comp, options?: Options) {
		this.push({ op: "overlay", component: component.id, options });
		return new Handle(this, this.overlays++);
	}
	hideOverlay() {
		this.push({ op: "hideTop" });
	}
	sendInput(data: string) {
		this.push({ op: "input", data });
	}
	renderAndFlush(assertions: () => void = () => {}) {
		this.push({ op: "render", width: this.columns, height: this.rows });
		this.checks.push(assertions);
	}
	check(assertions: () => void) {
		this.push({ op: "check" });
		this.checks.push(assertions);
	}
	async run() {
		let ran = 0;
		await replay(this.columns, this.rows, this.ops, (k, terminal, report) => {
			this.report = report;
			this.screen = terminal;
			this.checks[k]();
			ran += 1;
		});
		assert.strictEqual(ran, this.checks.length, "every render and check reported");
	}
}
const NC = "TUI overlay non-capturing";
const FOCUS = `${NC} › focus management`;
it(FOCUS, "non-capturing overlay preserves focus on creation", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	t.showOverlay(overlay, { nonCapturing: true });
	t.renderAndFlush(() => {
		assert.strictEqual(editor.focused, true);
		assert.strictEqual(overlay.focused, false);
	});
	return t.run();
});
it(FOCUS, "focus() transfers focus to the overlay", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const handle = t.showOverlay(overlay, { nonCapturing: true });
	handle.focus();
	t.renderAndFlush(() => {
		assert.strictEqual(editor.focused, false);
		assert.strictEqual(overlay.focused, true);
		assert.strictEqual(handle.isFocused(), true);
	});
	return t.run();
});
it(FOCUS, "unfocus() restores previous focus", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const handle = t.showOverlay(overlay, { nonCapturing: true });
	handle.focus();
	handle.unfocus();
	t.renderAndFlush(() => {
		assert.strictEqual(editor.focused, true);
		assert.strictEqual(overlay.focused, false);
		assert.strictEqual(handle.isFocused(), false);
	});
	return t.run();
});
it(FOCUS, "setHidden(false) on non-capturing overlay does not auto-focus", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const handle = t.showOverlay(overlay, { nonCapturing: true });
	handle.setHidden(true);
	handle.setHidden(false);
	t.renderAndFlush(() => {
		assert.strictEqual(editor.focused, true);
		assert.strictEqual(overlay.focused, false);
	});
	return t.run();
});
it(FOCUS, "hide() when overlay is not focused does not change focus", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const handle = t.showOverlay(overlay, { nonCapturing: true });
	handle.hide();
	t.renderAndFlush(() => assert.strictEqual(editor.focused, true));
	return t.run();
});
it(FOCUS, "hide() when focused restores focus correctly", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const handle = t.showOverlay(overlay, { nonCapturing: true });
	handle.focus();
	handle.hide();
	t.renderAndFlush(() => {
		assert.strictEqual(editor.focused, true);
		assert.strictEqual(overlay.focused, false);
	});
	return t.run();
});
it(FOCUS, "capturing overlay removed with non-capturing below restores focus to editor", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const nonCapturing = t.focusable(["NC"]);
	const capturing = t.focusable(["CAP"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	t.showOverlay(nonCapturing, { nonCapturing: true });
	const handle = t.showOverlay(capturing);
	t.check(() => assert.strictEqual(capturing.focused, true));
	handle.hide();
	t.renderAndFlush(() => {
		assert.strictEqual(editor.focused, true);
		assert.strictEqual(nonCapturing.focused, false);
	});
	return t.run();
});
it(FOCUS, "sub-overlay cleanup then hideOverlay restores focus and input to editor", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const timer = t.focusable(["TIMER"]);
	const controller = t.focusable(["CTRL"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const timerHandle = t.showOverlay(timer, { nonCapturing: true });
	t.showOverlay(controller);
	t.check(() => {
		assert.strictEqual(controller.focused, true);
		assert.strictEqual(editor.focused, false);
	});
	timerHandle.hide();
	t.hideOverlay();
	t.renderAndFlush(() => {
		assert.strictEqual(editor.focused, true);
		assert.strictEqual(controller.focused, false);
		assert.strictEqual(timer.focused, false);
	});
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(editor.inputs, ["x"]);
		assert.deepStrictEqual(controller.inputs, []);
		assert.deepStrictEqual(timer.inputs, []);
	});
	return t.run();
});
it(FOCUS, "removed focused child overlay does not become parent overlay fallback", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const child = t.focusable(["CHILD"]);
	const parent = t.focusable(["PARENT"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const childHandle = t.showOverlay(child, { nonCapturing: true });
	childHandle.focus();
	const parentHandle = t.showOverlay(parent);
	t.check(() => assert.strictEqual(parent.focused, true));
	childHandle.hide();
	parentHandle.hide();
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(editor.inputs, ["x"]);
		assert.deepStrictEqual(child.inputs, []);
		assert.deepStrictEqual(parent.inputs, []);
		assert.strictEqual(editor.focused, true);
	});
	return t.run();
});
// Adaptation: upstream schedules the controller's showOverlay as a microtask
// and awaits a promise around doneFn; the TUI calls those produce, in order,
// are written here directly.
it(FOCUS, "microtask-deferred sub-overlay pattern (showExtensionCustom simulation) restores focus", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const timer = t.focusable(["TIMER"]);
	const controller = t.focusable(["CTRL"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const timerHandle = t.showOverlay(timer, { nonCapturing: true });
	t.showOverlay(controller);
	t.renderAndFlush(() => {
		assert.strictEqual(controller.focused, true);
		assert.strictEqual(editor.focused, false);
	});
	// doneFn
	timerHandle.hide();
	t.hideOverlay();
	t.renderAndFlush(() => {
		assert.strictEqual(editor.focused, true, "editor should regain focus");
		assert.strictEqual(controller.focused, false);
		assert.strictEqual(timer.focused, false);
	});
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(editor.inputs, ["x"], "editor should receive input after close");
		assert.deepStrictEqual(controller.inputs, []);
	});
	return t.run();
});
it(FOCUS, "handleInput redirection skips non-capturing overlays when focused overlay becomes invisible", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const fallbackCapturing = t.focusable(["FALLBACK"]);
	const nonCapturing = t.focusable(["NC"]);
	const primary = t.focusable(["PRIMARY"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	t.showOverlay(fallbackCapturing);
	t.showOverlay(nonCapturing, { nonCapturing: true });
	const primaryHandle = t.showOverlay(primary, { visible: true });
	t.check(() => assert.strictEqual(primary.focused, true));
	primaryHandle.setVisible(false);
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(primary.inputs, []);
		assert.deepStrictEqual(nonCapturing.inputs, []);
		assert.deepStrictEqual(fallbackCapturing.inputs, ["x"]);
		assert.strictEqual(fallbackCapturing.focused, true);
	});
	return t.run();
});
it(FOCUS, "active base focus replacement receives close input before overlay restore", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const replacement = t.focusable(["REPLACEMENT"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.onInput(overlay, "b", () => t.setFocus(replacement));
	t.onInput(replacement, "\r", () => t.setFocus(editor));
	t.addChild(t.plain([]));
	t.setFocus(editor);
	t.showOverlay(overlay);
	t.check(() => assert.strictEqual(overlay.focused, true));
	t.sendInput("b");
	t.renderAndFlush(() => assert.strictEqual(replacement.focused, true));
	t.sendInput("\r");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(replacement.inputs, ["\r"]);
		assert.deepStrictEqual(overlay.inputs, ["b"]);
		assert.strictEqual(overlay.focused, true);
	});
	t.sendInput("x");
	t.renderAndFlush(() => assert.deepStrictEqual(overlay.inputs, ["b", "x"]));
	return t.run();
});
it(FOCUS, "active replacement still receives input when it is another overlay preFocus", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const replacement = t.focusable(["REPLACEMENT"]);
	const passive = t.focusable(["PASSIVE"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.onInput(overlay, "b", () => t.setFocus(replacement));
	t.onInput(replacement, "\r", () => t.setFocus(editor));
	t.addChild(t.plain([]));
	t.setFocus(editor);
	t.setFocus(replacement);
	t.showOverlay(passive, { nonCapturing: true });
	t.setFocus(editor);
	t.showOverlay(overlay);
	t.sendInput("b");
	t.renderAndFlush(() => assert.strictEqual(replacement.focused, true));
	t.sendInput("1");
	t.sendInput("\r");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(replacement.inputs, ["1", "\r"]);
		assert.deepStrictEqual(overlay.inputs, ["b"]);
		assert.strictEqual(overlay.focused, true);
	});
	return t.run();
});
// Adaptation: upstream's `base` Container is the TUI's only child; its
// children are added to the TUI directly here, so base.clear() and
// base.addChild(editor) become tui.clear() and tui.addChild(editor). Mounting
// and rendering are the same.
it(FOCUS, "blocked replacement can move focus internally before overlay restore", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const firstReplacement = t.focusable(["FIRST"]);
	const secondReplacement = t.focusable(["SECOND"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.onInput(overlay, "b", () => t.setFocus(firstReplacement));
	t.onInput(firstReplacement, "n", () => t.setFocus(secondReplacement));
	t.onInput(secondReplacement, "\r", () => {
		t.clear();
		t.addChild(editor);
		t.setFocus(editor);
	});
	t.addChild(editor);
	t.addChild(firstReplacement);
	t.addChild(secondReplacement);
	t.setFocus(editor);
	t.showOverlay(overlay);
	t.sendInput("b");
	t.renderAndFlush();
	t.sendInput("n");
	t.renderAndFlush();
	t.sendInput("2");
	t.sendInput("\r");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(overlay.inputs, ["b"]);
		assert.deepStrictEqual(firstReplacement.inputs, ["n"]);
		assert.deepStrictEqual(secondReplacement.inputs, ["2", "\r"]);
		assert.strictEqual(overlay.focused, true);
	});
	return t.run();
});
it(FOCUS, "removed replacement restores overlay even when overlay preFocus differs from next focus", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const palette = t.focusable(["PALETTE"]);
	const replacement = t.focusable(["REPLACEMENT"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.onInput(overlay, "b", () => t.setFocus(replacement));
	t.onInput(replacement, "\r", () => {
		t.clear();
		t.addChild(editor);
		t.setFocus(editor);
	});
	t.addChild(editor);
	t.addChild(palette);
	t.addChild(replacement);
	t.setFocus(palette);
	t.showOverlay(overlay);
	t.sendInput("b");
	t.renderAndFlush();
	t.sendInput("\r");
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(overlay.inputs, ["b", "x"]);
		assert.deepStrictEqual(replacement.inputs, ["\r"]);
		assert.deepStrictEqual(editor.inputs, []);
		assert.strictEqual(overlay.focused, true);
	});
	return t.run();
});
it(FOCUS, "unfocus target releases a blocked overlay while replacement remains focused", () => {
	const t = new Session();
	const fallback = t.focusable(["FALLBACK"]);
	const target = t.focusable(["TARGET"]);
	const replacement = t.focusable(["REPLACEMENT"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.onInput(replacement, "\r", () => t.setFocus(fallback));
	t.addChild(t.plain([]));
	const overlayHandle = t.showOverlay(overlay);
	t.onInput(overlay, "b", () => {
		t.setFocus(replacement);
		overlayHandle.unfocus({ target });
	});
	t.sendInput("b");
	t.renderAndFlush(() => assert.strictEqual(replacement.focused, true));
	t.sendInput("\r");
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(overlay.inputs, ["b"]);
		assert.deepStrictEqual(replacement.inputs, ["\r"]);
		assert.deepStrictEqual(fallback.inputs, []);
		assert.deepStrictEqual(target.inputs, ["x"]);
	});
	return t.run();
});
it(FOCUS, "handleInput restores focus to a visible focused overlay after base focus steal", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const replacement = t.focusable(["REPLACEMENT"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	t.showOverlay(overlay);
	t.check(() => assert.strictEqual(overlay.focused, true));
	t.setFocus(replacement);
	t.setFocus(editor);
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(overlay.inputs, ["x"]);
		assert.deepStrictEqual(editor.inputs, []);
		assert.strictEqual(overlay.focused, true);
	});
	return t.run();
});
it(FOCUS, "handleInput restores focus to explicitly focused raw sub-overlay after base focus steal", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const controller = t.focusable(["CONTROLLER"]);
	const subOverlay = t.focusable(["SUB"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	t.showOverlay(controller);
	const subHandle = t.showOverlay(subOverlay, { nonCapturing: true });
	subHandle.focus();
	t.setFocus(editor);
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(subOverlay.inputs, ["x"]);
		assert.deepStrictEqual(controller.inputs, []);
		assert.deepStrictEqual(editor.inputs, []);
	});
	return t.run();
});
it(FOCUS, "passive non-capturing overlay does not regain input after base focus", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const passive = t.focusable(["PASSIVE"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	t.showOverlay(passive, { nonCapturing: true });
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(editor.inputs, ["x"]);
		assert.deepStrictEqual(passive.inputs, []);
		assert.strictEqual(editor.focused, true);
	});
	return t.run();
});
it(FOCUS, "explicitly focused non-capturing overlay regains input after base focus steal", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const overlay = t.focusable(["NC"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const handle = t.showOverlay(overlay, { nonCapturing: true });
	handle.focus();
	t.setFocus(editor);
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(overlay.inputs, ["x"]);
		assert.deepStrictEqual(editor.inputs, []);
	});
	return t.run();
});
it(FOCUS, "unfocus() prevents visible overlay from regaining input", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const handle = t.showOverlay(overlay);
	handle.unfocus();
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(editor.inputs, ["x"]);
		assert.deepStrictEqual(overlay.inputs, []);
		assert.strictEqual(editor.focused, true);
	});
	return t.run();
});
it(FOCUS, "setFocus(null) explicitly clears visible overlay restore", () => {
	const t = new Session();
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	t.showOverlay(overlay);
	t.setFocus(null);
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(overlay.inputs, []);
		assert.strictEqual(overlay.focused, false);
	});
	return t.run();
});
it(FOCUS, "blocked replacement setFocus(null) resumes the visible overlay", () => {
	const t = new Session();
	const replacement = t.focusable(["REPLACEMENT"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.onInput(replacement, "\r", () => t.setFocus(null));
	t.onInput(overlay, "b", () => t.setFocus(replacement));
	t.addChild(t.plain([]));
	t.showOverlay(overlay);
	t.sendInput("b");
	t.renderAndFlush();
	t.sendInput("\r");
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(replacement.inputs, ["\r"]);
		assert.deepStrictEqual(overlay.inputs, ["b", "x"]);
		assert.strictEqual(overlay.focused, true);
	});
	return t.run();
});
it(FOCUS, "temporarily invisible focused overlay falls back without losing restore eligibility", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const handle = t.showOverlay(overlay, { visible: true });
	t.setFocus(editor);
	handle.setVisible(false);
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(editor.inputs, ["x"]);
		assert.deepStrictEqual(overlay.inputs, []);
	});
	handle.setVisible(true);
	t.sendInput("y");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(editor.inputs, ["x"]);
		assert.deepStrictEqual(overlay.inputs, ["y"]);
	});
	return t.run();
});
it(FOCUS, "temporarily invisible focused overlay with null preFocus restores when visible again", () => {
	const t = new Session();
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	const handle = t.showOverlay(overlay, { visible: true });
	handle.setVisible(false);
	t.sendInput("x");
	t.renderAndFlush(() => assert.deepStrictEqual(overlay.inputs, []));
	handle.setVisible(true);
	t.sendInput("y");
	t.renderAndFlush(() => assert.deepStrictEqual(overlay.inputs, ["y"]));
	return t.run();
});
it(FOCUS, "cyclic overlay preFocus ancestry does not hang focus changes", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	t.setFocus(overlay);
	const handle = t.showOverlay(overlay, { nonCapturing: true });
	handle.focus();
	t.setFocus(editor);
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(editor.inputs, ["x"]);
		assert.deepStrictEqual(overlay.inputs, []);
	});
	return t.run();
});
it(FOCUS, "handleInput restores the focus-order top overlay after base focus steal", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const lower = t.focusable(["LOWER"]);
	const upper = t.focusable(["UPPER"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const lowerHandle = t.showOverlay(lower);
	t.showOverlay(upper);
	lowerHandle.focus();
	t.setFocus(editor);
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(lower.inputs, ["x"]);
		assert.deepStrictEqual(upper.inputs, []);
		assert.deepStrictEqual(editor.inputs, []);
	});
	return t.run();
});
it(FOCUS, "hideOverlay() does not reassign focus when topmost overlay is non-capturing", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const capturing = t.focusable(["CAP"]);
	const nonCapturing = t.focusable(["NC"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	t.showOverlay(capturing);
	t.showOverlay(nonCapturing, { nonCapturing: true });
	t.check(() => assert.strictEqual(capturing.focused, true));
	t.hideOverlay();
	t.renderAndFlush(() => assert.strictEqual(capturing.focused, true));
	return t.run();
});
it(FOCUS, "multiple capturing and non-capturing overlays restore focus through removals", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const c1 = t.focusable(["C1"]);
	const n1 = t.focusable(["N1"]);
	const c2 = t.focusable(["C2"]);
	const n2 = t.focusable(["N2"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const c1Handle = t.showOverlay(c1);
	t.showOverlay(n1, { nonCapturing: true });
	const c2Handle = t.showOverlay(c2);
	t.showOverlay(n2, { nonCapturing: true });
	t.check(() => assert.strictEqual(c2.focused, true));
	c2Handle.hide();
	t.renderAndFlush(() => assert.strictEqual(c1.focused, true));
	c1Handle.hide();
	t.renderAndFlush(() => assert.strictEqual(editor.focused, true));
	return t.run();
});
it(FOCUS, "capturing overlay unfocus() on topmost capturing overlay falls back to preFocus", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const capturing = t.focusable(["CAP"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const handle = t.showOverlay(capturing);
	t.check(() => assert.strictEqual(capturing.focused, true));
	handle.unfocus();
	t.renderAndFlush(() => {
		assert.strictEqual(editor.focused, true);
		assert.strictEqual(capturing.focused, false);
	});
	return t.run();
});

const GUARDS = `${NC} › no-op guards`;
it(GUARDS, "focus() on hidden overlay is a no-op", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const handle = t.showOverlay(overlay, { nonCapturing: true });
	handle.setHidden(true);
	handle.focus();
	t.renderAndFlush(() => {
		assert.strictEqual(editor.focused, true);
		assert.strictEqual(handle.isFocused(), false);
	});
	return t.run();
});
it(GUARDS, "focus() after hide() is a no-op", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const handle = t.showOverlay(overlay, { nonCapturing: true });
	handle.hide();
	handle.focus();
	t.renderAndFlush(() => {
		assert.strictEqual(editor.focused, true);
		assert.strictEqual(handle.isFocused(), false);
	});
	return t.run();
});
it(GUARDS, "unfocus() when overlay does not have focus is a no-op", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const handle = t.showOverlay(overlay, { nonCapturing: true });
	handle.unfocus();
	t.renderAndFlush(() => {
		assert.strictEqual(editor.focused, true);
		assert.strictEqual(overlay.focused, false);
	});
	return t.run();
});
it(GUARDS, "unfocus() with null preFocus clears focus and does not route input back to overlay", () => {
	const t = new Session();
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	const handle = t.showOverlay(overlay);
	t.check(() => assert.strictEqual(overlay.focused, true));
	handle.unfocus();
	t.check(() => assert.strictEqual(overlay.focused, false));
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(overlay.inputs, []);
		assert.strictEqual(handle.isFocused(), false);
	});
	return t.run();
});

const CYCLE = `${NC} › focus cycle prevention`;
it(CYCLE, "toggle focus between non-capturing overlays then unfocus returns to editor", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const a = t.focusable(["A"]);
	const b = t.focusable(["B"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const aHandle = t.showOverlay(a, { nonCapturing: true });
	const bHandle = t.showOverlay(b, { nonCapturing: true });
	aHandle.focus();
	bHandle.focus();
	aHandle.focus();
	aHandle.unfocus();
	t.renderAndFlush(() => {
		assert.strictEqual(editor.focused, true);
		assert.strictEqual(a.focused, false);
		assert.strictEqual(b.focused, false);
	});
	return t.run();
});
it(CYCLE, "explicit unfocus target supports cycling between three overlays and editor", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const a = t.focusable(["A"]);
	const b = t.focusable(["B"]);
	const c = t.focusable(["C"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const aHandle = t.showOverlay(a);
	const bHandle = t.showOverlay(b);
	const cHandle = t.showOverlay(c);
	aHandle.focus();
	t.sendInput("a");
	t.renderAndFlush();
	bHandle.focus();
	t.sendInput("b");
	t.renderAndFlush();
	cHandle.focus();
	t.sendInput("c");
	t.renderAndFlush();
	cHandle.unfocus({ target: editor });
	t.sendInput("e");
	t.renderAndFlush();
	aHandle.focus();
	t.sendInput("A");
	t.renderAndFlush();
	aHandle.unfocus({ target: editor });
	t.sendInput("E");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(a.inputs, ["a", "A"]);
		assert.deepStrictEqual(b.inputs, ["b"]);
		assert.deepStrictEqual(c.inputs, ["c"]);
		assert.deepStrictEqual(editor.inputs, ["e", "E"]);
		assert.strictEqual(editor.focused, true);
	});
	return t.run();
});
it(CYCLE, "explicit null unfocus target clears focus without restoring overlays", () => {
	const t = new Session();
	const overlay = t.focusable(["OVERLAY"]);
	t.addChild(t.plain([]));
	const handle = t.showOverlay(overlay);
	handle.unfocus({ target: null });
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(overlay.inputs, []);
		assert.strictEqual(handle.isFocused(), false);
	});
	return t.run();
});
it(CYCLE, "hiding focused overlay falls back to next visual-frontmost overlay", () => {
	const t = new Session();
	const editor = t.focusable(["EDITOR"]);
	const a = t.focusable(["A"]);
	const b = t.focusable(["B"]);
	const c = t.focusable(["C"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const aHandle = t.showOverlay(a);
	const bHandle = t.showOverlay(b);
	t.showOverlay(c);
	aHandle.focus();
	bHandle.focus();
	bHandle.setHidden(true);
	t.sendInput("x");
	t.renderAndFlush(() => {
		assert.deepStrictEqual(a.inputs, ["x"]);
		assert.deepStrictEqual(c.inputs, []);
		assert.strictEqual(a.focused, true);
	});
	return t.run();
});

const ORDER = `${NC} › rendering order`;
const cell = { row: 0, col: 0, width: 1 };
it(ORDER, "focus() on already-focused overlay bumps visual order", () => {
	const t = new Session(20, 6);
	const editor = t.focusable(["EDITOR"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const aHandle = t.showOverlay(t.plain(["A"]), { ...cell, nonCapturing: true });
	t.showOverlay(t.plain(["B"]), { ...cell, nonCapturing: true });
	aHandle.focus();
	t.showOverlay(t.plain(["C"]), { ...cell, nonCapturing: true });
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "C"));
	aHandle.focus();
	t.renderAndFlush(() => {
		assert.strictEqual(t.viewport()[0]?.charAt(0), "A");
		assert.strictEqual(aHandle.isFocused(), true);
	});
	return t.run();
});
it(ORDER, "default rendering order for overlapping overlays follows creation order", () => {
	const t = new Session(20, 6);
	t.addChild(t.plain([]));
	t.showOverlay(t.plain(["A"]), { ...cell, nonCapturing: true });
	t.showOverlay(t.plain(["B"]), { ...cell, nonCapturing: true });
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "B"));
	return t.run();
});
it(ORDER, "focus() on lower overlay renders it on top", () => {
	const t = new Session(20, 6);
	t.addChild(t.plain([]));
	const lower = t.showOverlay(t.plain(["A"]), { ...cell, nonCapturing: true });
	t.showOverlay(t.plain(["B"]), { ...cell, nonCapturing: true });
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "B"));
	lower.focus();
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "A"));
	return t.run();
});
it(ORDER, "focusing middle overlay places it on top while preserving others relative order", () => {
	const t = new Session(20, 6);
	t.addChild(t.plain([]));
	t.showOverlay(t.plain(["A"]), { ...cell, nonCapturing: true });
	const middle = t.showOverlay(t.plain(["B"]), { ...cell, nonCapturing: true });
	const top = t.showOverlay(t.plain(["C"]), { ...cell, nonCapturing: true });
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "C"));
	middle.focus();
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "B"));
	middle.hide();
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "C"));
	top.hide();
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "A"));
	return t.run();
});
it(ORDER, "capturing overlay hidden and shown again renders on top after unhide", () => {
	const t = new Session(20, 6);
	t.addChild(t.plain([]));
	t.showOverlay(t.plain(["A"]), { ...cell, nonCapturing: true });
	const capturing = t.showOverlay(t.plain(["B"]), cell);
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "B"));
	capturing.setHidden(true);
	t.showOverlay(t.plain(["C"]), { ...cell, nonCapturing: true });
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "C"));
	capturing.setHidden(false);
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "B"));
	return t.run();
});
it(ORDER, "unfocus() does not change visual order until another overlay is focused", () => {
	const t = new Session(20, 6);
	const editor = t.focusable(["EDITOR"]);
	t.addChild(t.plain([]));
	t.setFocus(editor);
	const a = t.showOverlay(t.plain(["A"]), { ...cell, nonCapturing: true });
	const b = t.showOverlay(t.plain(["B"]), { ...cell, nonCapturing: true });
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "B"));
	a.focus();
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "A"));
	a.unfocus();
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "A"));
	b.focus();
	t.renderAndFlush(() => assert.strictEqual(t.viewport()[0]?.charAt(0), "B"));
	return t.run();
});

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
