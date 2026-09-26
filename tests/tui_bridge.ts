// Test-only adapters for running original upstream tui test bodies against
// native components. Every Editor/Input/SelectList/SettingsList call is one
// synchronous JSON-line request to tests/tui-bridge.bend (Bun lane, or a native
// binary with TUI_BRIDGE="path [args]"); theme functions and component
// callbacks come back as {"call": ...} lines while a request is pending and
// are answered synchronously, so they run inside the native operation exactly
// where upstream calls them. No production behavior comes from here:
// TuiMainScreen/VirtualTerminal only carry the terminal size the editor reads,
// and the keybinding manager only carries user bindings.
//
// Adaptation: native cursor columns and wrap indices count Unicode scalars;
// they are converted to upstream's UTF-16 units here (tests/editor.md).
import { spawn, spawnSync } from "node:child_process";
import { closeSync, mkdtempSync, openSync, readSync, rmSync, writeSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const ROOT = path.resolve(import.meta.dir, "..");

function command(): string[] {
	if (process.env.TUI_BRIDGE) {
		const [binary, ...args] = process.env.TUI_BRIDGE.split(" ");
		return [path.resolve(ROOT, binary), ...args];
	}
	const out = path.join(ROOT, "build/tui-bridge.js");
	if (!process.env.TUI_BRIDGE_PREBUILT) {
		const built = spawnSync(path.join(ROOT, "build/bend-native-toolchain/bend2/main.ts"), [path.join(ROOT, "tests/tui-bridge.bend"), "-o", out], { encoding: "utf8" });
		if (built.status !== 0) throw new Error(`bridge build failed: ${built.stdout}${built.stderr}`);
	}
	return [process.execPath, out];
}

type Call = { call: string; object: number; text: string; selected?: boolean; id?: string; value?: string };
type Handler = (call: Call) => unknown;

class Bridge {
	private request: number;
	private response: number;
	private buffer = Buffer.alloc(0);
	private directory: string;
	handlers = new Map<number, Handler>();

	constructor() {
		this.directory = mkdtempSync(path.join(tmpdir(), "tui-bridge-"));
		const req = path.join(this.directory, "req");
		const resp = path.join(this.directory, "resp");
		spawnSync("mkfifo", [req, resp]);
		const quoted = command().map((part) => `'${part.replaceAll("'", "'\\''")}'`).join(" ");
		const child = spawn("sh", ["-c", `exec ${quoted} < '${req}' > '${resp}'`], { cwd: ROOT, stdio: ["ignore", "ignore", "inherit"] });
		child.unref();
		this.request = openSync(req, "w");
		this.response = openSync(resp, "r");
	}

	private line(): string {
		for (;;) {
			const end = this.buffer.indexOf(10);
			if (end >= 0) {
				const text = this.buffer.subarray(0, end).toString("utf8");
				this.buffer = this.buffer.subarray(end + 1);
				return text;
			}
			const chunk = Buffer.alloc(1 << 16);
			const count = readSync(this.response, chunk, 0, chunk.length, null);
			if (count === 0) throw new Error("tui bridge exited");
			this.buffer = Buffer.concat([this.buffer, chunk.subarray(0, count)]);
		}
	}

	private send(value: unknown) {
		const bytes = Buffer.from(`${JSON.stringify(value)}\n`);
		let at = 0;
		while (at < bytes.length) at += writeSync(this.request, bytes, at, bytes.length - at);
	}

	call(op: string, fields: Record<string, unknown> = {}): any {
		this.send({ op, ...fields });
		for (;;) {
			const message = JSON.parse(this.line());
			if ("call" in message) {
				const handler = this.handlers.get(message.object);
				if (!handler) throw new Error(`no callback handler for object ${message.object}`);
				this.send({ value: handler(message) ?? null });
				continue;
			}
			if ("error" in message) throw new Error(`native component: ${message.error}`);
			return message.result;
		}
	}

	close() {
		closeSync(this.request);
		closeSync(this.response);
		rmSync(this.directory, { recursive: true, force: true });
	}
}

let shared: Bridge | undefined;
export function bridge(): Bridge {
	shared ??= new Bridge();
	return shared;
}
export function closeBridge() {
	shared?.close();
	shared = undefined;
}

// UTF-16 length of the first `scalars` scalars of `text`.
function units(text: string, scalars: number): number {
	let length = 0;
	let count = 0;
	for (const char of text) {
		if (count === scalars) break;
		length += char.length;
		count++;
	}
	return length;
}

export class VirtualTerminal {
	constructor(
		public columns = 80,
		public rows = 24,
	) {}
}
export class TuiMainScreen {
	constructor(public terminal: VirtualTerminal) {}
	requestRender() {}
}

type Theme = {
	borderColor: (text: string) => string;
	selectList: Record<string, (text: string) => string>;
};

export class Editor {
	readonly id: number;
	private submit?: (text: string) => void;
	private change?: (text: string) => void;
	private focusedValue = false;
	private disabled = false;

	constructor(tui: TuiMainScreen, theme: Theme, options: { paddingX?: number; autocompleteMaxVisible?: number } = {}) {
		const b = bridge();
		this.id = b.call("new", { kind: "editor", rows: tui.terminal.rows, options });
		b.handlers.set(this.id, ({ call, text }) => {
			if (call === "borderColor") return theme.borderColor(text);
			if (call === "onSubmit") return void this.submit?.(text);
			if (call === "onChange") return void this.change?.(text);
			return theme.selectList[call](text);
		});
	}

	private op(name: string, fields: Record<string, unknown> = {}) {
		return bridge().call(name, { object: this.id, ...fields });
	}
	private callbacks() {
		this.op("setCallbacks", { onSubmit: this.submit !== undefined, onChange: this.change !== undefined });
	}

	get onSubmit() {
		return this.submit;
	}
	set onSubmit(callback: ((text: string) => void) | undefined) {
		this.submit = callback;
		this.callbacks();
	}
	get onChange() {
		return this.change;
	}
	set onChange(callback: ((text: string) => void) | undefined) {
		this.change = callback;
		this.callbacks();
	}
	get focused() {
		return this.focusedValue;
	}
	set focused(value: boolean) {
		this.focusedValue = value;
		this.op("setFocused", { value });
	}
	get disableSubmit() {
		return this.disabled;
	}
	set disableSubmit(value: boolean) {
		this.disabled = value;
		this.op("setDisableSubmit", { value });
	}

	handleInput(data: string): void {
		this.op("input", { data });
	}
	getText(): string {
		return this.op("getText");
	}
	getExpandedText(): string {
		return this.op("getExpandedText");
	}
	getLines(): string[] {
		return this.op("getLines");
	}
	getCursor(): { line: number; col: number } {
		const { line, col } = this.op("getCursor");
		return { line, col: units(this.getLines()[line] ?? "", col) };
	}
	setText(text: string): void {
		this.op("setText", { text });
	}
	insertTextAtCursor(text: string): void {
		this.op("insertTextAtCursor", { text });
	}
	addToHistory(text: string): void {
		this.op("addToHistory", { text });
	}
	render(width: number): string[] {
		return this.op("render", { width });
	}
	isShowingAutocomplete(): boolean {
		return this.op("isShowingAutocomplete");
	}
	handleMouse(event: MouseEvent) {
		return this.op("handleMouse", { event }) ?? undefined;
	}
	invalidate(): void {}
	setAutocompleteProvider(): void {
		throw new Error("autocomplete providers are not bridged (tests/editor.md)");
	}
}

// Upstream's optional pre-segmentation marks paste markers atomic; the native
// wrapper takes the paste registry instead, so each multi-grapheme segment
// must be a paste marker, whose id is registered.
const graphemes = new Intl.Segmenter();
export function wordWrapLine(line: string, maxWidth: number, preSegmented?: Intl.SegmentData[]) {
	const pastes: number[] = [];
	for (const segment of preSegmented ?? []) {
		if ([...graphemes.segment(segment.segment)].length === 1) continue;
		const marker = /^\[paste #(\d+)( (\+\d+ lines|\d+ chars))?\]$/.exec(segment.segment);
		if (!marker) throw new Error(`pre-segmented input other than paste markers is not bridged: ${segment.segment}`);
		pastes.push(Number(marker[1]));
	}
	const chunks: { text: string; startIndex: number; endIndex: number }[] = bridge().call("wordWrapLine", { line, width: maxWidth, pastes });
	return chunks.map((chunk) => ({ text: chunk.text, startIndex: units(line, chunk.startIndex), endIndex: units(line, chunk.endIndex) }));
}

export function visibleWidth(text: string): number {
	return bridge().call("visibleWidth", { text });
}

export const TUI_KEYBINDINGS = { tui: true };
export class KeybindingsManager {
	constructor(
		public definitions: unknown,
		public userBindings: Record<string, string | string[]> = {},
	) {
		if (definitions !== TUI_KEYBINDINGS) throw new Error("only the TUI keybinding definitions are bridged");
	}
}
export function setKeybindings(manager: KeybindingsManager) {
	bridge().call("keybindings", { bindings: manager.userBindings });
}

type MouseEvent = Record<string, unknown>;

export class Input {
	readonly id: number;
	constructor() {
		this.id = bridge().call("new", { kind: "input" });
	}
	private op(name: string, fields: Record<string, unknown> = {}) {
		return bridge().call(name, { object: this.id, ...fields });
	}
	getValue(): string {
		return this.op("getValue");
	}
	setValue(value: string): void {
		this.op("setValue", { value });
	}
	render(width: number): string[] {
		return this.op("render", { width });
	}
	handleInput(data: string): void {
		this.op("input", { data });
	}
	handleMouse(event: MouseEvent) {
		return this.op("handleMouse", { event }) ?? undefined;
	}
	invalidate(): void {}
}

type SelectItem = { value: string; label: string; description?: string };
export class SelectList {
	readonly id: number;
	private callbacks: Record<string, ((item?: SelectItem) => void) | undefined> = {};
	constructor(
		private items: SelectItem[],
		maxVisible: number,
		theme: Record<string, (text: string) => string>,
	) {
		const b = bridge();
		this.id = b.call("new", { kind: "select", items, maxVisible });
		b.handlers.set(this.id, ({ call, text }) => {
			if (call in theme) return theme[call](text);
			const callback = this.callbacks[call];
			return void callback?.(call === "onCancel" ? undefined : this.items.find((entry) => entry.value === text));
		});
	}
	private op(name: string, fields: Record<string, unknown> = {}) {
		return bridge().call(name, { object: this.id, ...fields });
	}
	private listen(name: string, callback: ((item?: SelectItem) => void) | undefined) {
		this.callbacks[name] = callback;
		this.op("setCallbacks", Object.fromEntries(["onSelect", "onCancel", "onSelectionChange"].map((key) => [key, this.callbacks[key] !== undefined])));
	}
	set onSelect(callback: ((item: SelectItem) => void) | undefined) {
		this.listen("onSelect", callback as (item?: SelectItem) => void);
	}
	set onCancel(callback: (() => void) | undefined) {
		this.listen("onCancel", callback);
	}
	set onSelectionChange(callback: ((item: SelectItem) => void) | undefined) {
		this.listen("onSelectionChange", callback as (item?: SelectItem) => void);
	}
	getSelectedItem(): SelectItem | null {
		return this.op("getSelectedItem");
	}
	setSelectedIndex(index: number): void {
		this.op("setSelectedIndex", { index });
	}
	render(width: number): string[] {
		return this.op("render", { width });
	}
	handleInput(data: string): void {
		this.op("input", { data });
	}
	handleMouse(event: MouseEvent) {
		return this.op("handleMouse", { event }) ?? undefined;
	}
	invalidate(): void {}
}

type SettingItem = { id: string; label: string; description?: string; currentValue: string; values?: string[] };
type SettingsTheme = {
	label: (text: string, selected: boolean) => string;
	value: (text: string, selected: boolean) => string;
	description: (text: string) => string;
	cursor: string;
	hint: (text: string) => string;
};
export class SettingsList {
	readonly id: number;
	constructor(items: SettingItem[], maxVisible: number, theme: SettingsTheme, onChange: (id: string, value: string) => void, onCancel: () => void, options: { enableSearch?: boolean } = {}) {
		if (items.some((entry) => "submenu" in entry)) throw new Error("setting submenus are not bridged");
		const b = bridge();
		this.id = b.call("new", { kind: "settings", items, maxVisible, cursor: theme.cursor, enableSearch: options.enableSearch ?? false });
		b.handlers.set(this.id, ({ call, text, selected, id, value }) => {
			if (call === "label" || call === "value") return theme[call](text, selected ?? false);
			if (call === "description" || call === "hint") return theme[call](text);
			if (call === "onChange") return void onChange(id!, value!);
			if (call === "onCancel") return void onCancel();
			throw new Error(`unexpected settings callback ${call}`);
		});
	}
	private op(name: string, fields: Record<string, unknown> = {}) {
		return bridge().call(name, { object: this.id, ...fields });
	}
	selectItem(id: string): void {
		this.op("selectItem", { id });
	}
	render(width: number): string[] {
		return this.op("render", { width });
	}
	handleInput(data: string): void {
		this.op("input", { data });
	}
	handleMouse(event: MouseEvent) {
		return this.op("handleMouse", { event }) ?? undefined;
	}
	invalidate(): void {}
}

// Container and TuiAltScreen exist so modules defining classes over them load;
// the alternate-screen mouse tests that construct them remain pending.
export class Container {
	children: unknown[] = [];
	addChild(child: unknown) {
		this.children.push(child);
	}
}
export class TuiAltScreen {
	constructor() {
		throw new Error("TuiAltScreen is not bridged (tests/editor.md)");
	}
}

export class CombinedAutocompleteProvider {
	constructor() {
		throw new Error("autocomplete providers are not bridged (tests/editor.md)");
	}
}
