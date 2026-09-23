# SelectList

`packages/tui/src/components/select-list.bend` ports `packages/tui/src/components/select-list.ts` from pinned pi-mono revision `46c9de402`. Items retain `value`, `label` and optional `description`; theme and layout retain all upstream fields. `setFilter` uses exact Unicode default lowercase followed by prefix comparison of item values, preserving input order. This component does not perform fuzzy ranking. The native `CaseMap.lower` dependency handles final sigma and dotted-I expansion.

State updates are immutable. `new`, `setFilter`, `setSelectedIndex`, `setCallbacks` and `invalidate` return state. `getSelectedItem` returns `Maybe<SelectItem>`. `render` returns `IO(List<String>)`, because theme and custom truncation callbacks may have effects; `handleInput` returns `IO(SelectList)`, and `handleMouse` returns `IO(SelectList & Maybe<TuiMouseEventResult>)`. Callers retain the new state. Callback handles are borrowed and caller-owned, including every theme field, optional `truncatePrimary`, `onSelect`, `onCancel` and `onSelectionChange`; the component does not dispose them. Keybindings and keyboard protocol context are explicit `handleInput` arguments instead of global state.

Viewport dimensions, padding bounds and selected indices use `Nat`. The two custom-truncation context widths use shared `Tui.Offset`, preserving the negative values upstream passes when terminal width is below four. `Forward n` means nonnegative n and `Backward n` means negative n. Actual native truncation clamps negative budgets to zero. Mouse events/results use the shared `tui.bend` types. Empty-list navigation need not preserve upstream's private negative index: no item exists, no selection callback fires, and changing the filter resets the index. The externally meaningful empty-list behavior is checked against upstream.

Callback ordering matches the source, including a first custom truncation followed by a second fallback call when the description column cannot fit. The unused `selectedPrefix` theme field is retained and never invoked, as upstream. Keyboard movement wraps and notifies even for a single selected item; wheel movement clamps and notifies only on change. Mouse press saves the item index before centered scrolling moves rows; click uses that saved index. Filtering retains the pending press index, matching the source even when the index no longer identifies an item. Hover does not change selection.

`tests/select_list_reference.ts` verifies hashes of the component, utilities, keybindings, keys and original test file before executing all five original named tests unchanged. Each render observation is replayed by the native fixture with exact strings and ordered callback arguments. The checker adds 235 deterministic sequences covering widths zero through 100, layout bounds, custom truncation and fallback, labels/description whitespace/ANSI/wide characters, filtering and Unicode lowercase distinctions, scrolling, remapped-key precedence, absent listeners, cancellation and mouse transitions. Every action records the selected item; renders and mouse results are also compared. The fixture covers these modules independently, not renderer ownership/focus integration or complete TUI parity.

All five original tests and 235 supplemental sequences pass on Bun and O1 native with one and four threads. The test-only reference dependency `get-east-asian-width` belongs in `build/select-reference/node_modules`. Build and run with the installed native toolchain:

```sh
bun "$BEND" tests/select-list.bend -o build/select-list.js
BEND="$BEND" sh scripts/build-pure.sh tests/select-list.bend build/select-list
python3 tests/select_list_check.py
```

Use `--prefix` to select isolated build artifacts; positional backend arguments select `bun`, `native-1` or `native-4`. The default runs all three.
