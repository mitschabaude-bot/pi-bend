# Input component

`packages/tui/src/components/input.bend` ports the pinned `pi-mono` revision `46c9de402` single-line Input component. It supports configurable prompt/placeholder styling, focus cursor marker, horizontal scrolling, mouse cursor placement, grapheme movement/deletion, checked word movement/deletion, Emacs kill/yank rotation, undo coalescing, remapped keys, Kitty printable input and chunked bracketed paste. The existing native kill-ring, undo-stack, grapheme, ANSI layout and keyboard modules provide their respective behavior.

State is immutable. `new`, `setValue`, `setFocused`, `setCallbacks` and `invalidate` return state; `getValue` returns the current text. `handleMouse` returns the state and optional shared mouse result. `render` returns `IO(Input & List<String>)`, updating the scroll origin used by later mouse input and invoking the optional placeholder-style callback in source order. Submit, escape and placeholder-style callback handles are borrowed and remain caller-owned; render/input never dispose them. `handleInput` receives explicit keybindings, keyboard protocol state and a checked word-segmenter context, returning `IO(Word.ResultOf(Input))`.

Word segmentation is a dependency, not an ASCII or UAX approximation: the injected segment function returns `Word.ResultOf(List<Word.Segment>)`, and unsupported language engines propagate as `MissingWordEngine`. The original word-navigation API's atomic predicate is preserved. This milestone validates Input's use of that interface with exact source lexical fixtures, including the original CJK deletion cases; it does not claim a completed default Intl dictionary/LSTM replacement. The renderer owns connecting a native segmentation context and handling its errors. No test-only host segmentation runs in production.

Native cursor positions and undo snapshots count Unicode scalars instead of UTF-16 units, retaining whole scalar values. Cursor movement/deletion uses grapheme boundaries. The reference explicitly converts inspected cursor positions to scalar offsets. Source behavior is retained for empty input, end/start no-ops, setValue preserving undo/kill history, no-op word moves retaining the previous action, space-separated undo coalescing, paste cleanup, callbacks, and prior scroll-origin retention while rendering a placeholder or a prompt wider than the terminal. Mouse placement retains the source's fixed two-column prompt offset even with a custom prompt.

All 36 named `input.test.ts` tests execute with their original assertions against hash-pinned source, producing 47 native-replayed traces. The reference records exact input/value/render/mouse observations and callback arguments, and captures the lexical segmentation consumed by each word operation. A further 274 deterministic sequences cover remapped keys, Kitty input, controls, undo/yank histories, Unicode/wide rendering, mouse positioning, every split of several paste streams, nested/trailing paste markers, a 30,000-character pasted line and a 10,000-mark grapheme. An independent missing-engine case checks error propagation without modifying text. All checks pass on Bun and O1 native with one and four threads.

Eleven render observations intentionally retain the previously approved scanner corrections from `tests/ansi-utils.md`. Moving the cursor inside a programmatically supplied CSI sequence leaves literal `[`/`[3` fragments; native width counts them rather than swallowing them. A complete bracketed-paste CSI retained inside pasted data is zero-width under complete CSI grammar. Exact independent expectations cover those cases; every original Input test remains unchanged.

Long-line validation exposed an existing Base/backend limitation: `String.length(String.take(repeat(30000,"x"),30000))` faults on Bun with a machine-stack-overflow message, while the native Input fixture passes. Input uses one tail-recursive accumulator for scalar prefix slices, avoiding that path without changing its API or semantics. The compiler limitation remains unresolved; no compiler change was attempted. The regression remains the real long-paste/render/undo sequence, alongside a long grapheme case.

Build using the installed compiler and the test-only `get-east-asian-width` dependency under `build/input-reference/node_modules`:

```sh
bun "$BEND" tests/input.bend -o build/input.js
BEND="$BEND" BEND_TUS=8 sh scripts/build-pure.sh tests/input.bend build/input
python3 tests/input_check.py
```

The checker defaults to Bun and O1 native with one/four threads; positional backend names and `--prefix` select isolated artifacts. Component adapter ownership and default lexical-engine integration are separate from this fixture.
