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
