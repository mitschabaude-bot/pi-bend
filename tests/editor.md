# Native Editor component

`packages/tui/src/components/editor.bend` ports the pinned pi-mono Editor as an immutable state machine plus explicit IO for callbacks and asynchronous autocomplete. Its public operations cover text and expanded paste markers, history, focus and submit settings, rendering, keyboard dispatch, bracketed paste, completion, and mouse placement. The editor borrows provider and callback handles; its owner retires those handles after `dispose` completes. The keyboard path takes an injected keybinding manager and word segmenter, so neither key configuration nor word behavior is hidden in a global service.

The differential fixtures hash-check the pinned upstream `editor.ts`. `editor_wrap_check.py` compares 830 wrap cases, `editor_edit_check.py` compares 8,025 editing transitions, `editor_component_check.py` compares 180 rendered cases, and `editor_input_check.py` compares 4,856 keyboard, history, paste, callback, and mouse transitions. The input fixture records source word segmentation as explicit test data for the injected Bend segmenter; it does not supply production behavior. `editor-autocomplete.bend` checks serialized requests, stale-result rejection, current snapshots, abortable debounce, and resource retirement on Bun and native backends.

Internal offsets use Unicode scalar positions. The vertical cursor adapter translates between those positions and upstream's UTF-16 positions at wrapped-line movement; this preserves source behavior around astral characters without imposing UTF-16 offsets on the public Bend model. A grapheme wider than the viewport stays intact; the pinned source loops indefinitely on that input, so the wrap fixture records three corrective cases separately. Native word boundaries depend on the injected segmenter, and the broader public TUI wiring and upstream Editor suite inventory remain integration work.

```sh
TOOLCHAIN=/home/agent/code/pi-bend-terminal/build/bend-native-toolchain/bend2/main.ts
WIDTH=/home/agent/code/pi-bend-tui-text/build/text-reference/node_modules/get-east-asian-width/index.js
$TOOLCHAIN tests/editor-input.bend -o build/editor-input.js
python3 tests/editor_input_check.py --width-reference "$WIDTH" -- bun build/editor-input.js
BEND="$TOOLCHAIN" BEND_TUS=4 sh scripts/build-pure.sh tests/editor-input.bend build/editor-input
python3 tests/editor_input_check.py --width-reference "$WIDTH" -- build/editor-input --threads 1
python3 tests/editor_input_check.py --width-reference "$WIDTH" -- build/editor-input --threads 4
```

## Original upstream suites through the component bridge

`tests/tui_original.ts` executes the pinned `editor.test.ts`, `editor-history-keybindings.test.ts` and `mouse-components.test.ts` files themselves (hash-checked), with only their implementation imports redirected: `Editor`, `Input`, `SelectList`, `SettingsList`, `wordWrapLine`, `visibleWidth` and `setKeybindings` go to `tests/tui_bridge.ts`, which forwards every call as one synchronous JSON line to `tests/tui-bridge.bend`. Theme functions and component callbacks (`onSubmit`, `onChange`, `onSelect`, `onSelectionChange`, `onCancel`) are called back from inside the native operation and answered synchronously, so callback order is upstream's. Editor and input keys pass through the same segmenter preparation as the live components. `TuiMainScreen`/`VirtualTerminal` only carry the terminal rows the editor reads; the test themes are upstream's own. `tests/original_harness.ts` stands in for `node:test` and keeps full describe/it names; tests listed as pending are reported by name and never counted as passed.

Adaptations: cursor columns and wrap chunk indices are native scalar offsets, converted to UTF-16 units for the original assertions. `wordWrapLine`'s optional pre-segmentation exists upstream to make paste markers atomic; the native wrapper takes the paste registry instead, so the bridge registers the ids of the pre-segmented markers (any other multi-grapheme segment is rejected rather than approximated).

Results on Bun and native one/four threads: `editor.test.ts` 166 of 192 pass, `editor-history-keybindings.test.ts` 1 of 1, `mouse-components.test.ts` 7 of 10. Pending: the 26 editor autocomplete tests (the `Autocomplete` group, `undoes autocomplete`, `does not trigger autocomplete during single-line paste`) need asynchronous providers and `t.mock.timers`, which the synchronous bridge cannot drive, and the native debounce uses the real timer; the three alternate-screen mouse tests need `TuiAltScreen` dispatch through a virtual terminal. The editor suite exposed three differences, now fixed in `editor.bend`: Right at the end of the last line records the sticky visual column, and moving down onto a later visual line of an already visited paste marker skips its remaining visual lines (upstream's `moveToVisualLine` retry, including its partially moved restart state; a negative intermediate column saturates at zero natively).

```sh
bun tests/tui_original.ts
BEND_TUS=8 flock /tmp/pi-bend-build.lock sh scripts/build-pure.sh tests/tui-bridge.bend build/tui-bridge
TUI_BRIDGE="build/tui-bridge --threads 1" bun tests/tui_original.ts
TUI_BRIDGE="build/tui-bridge --threads 4" bun tests/tui_original.ts
```
