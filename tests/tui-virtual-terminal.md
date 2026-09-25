# Upstream TUI suites on a virtual terminal

`tests/tui-virtual-terminal.bend` drives the native TUI (`tui-base` composition, overlays, and the main-screen planner that `tui-process` uses) through a JSON script of operations. It prints each render's ordered terminal writes. `tests/tui_virtual_terminal.ts` replays them into upstream's own `VirtualTerminal` (xterm headless, from the pinned pi-mono checkout) and applies each upstream test's assertions under its original suite and test name. The oracle is test-only.

```sh
bun tests/tui_virtual_terminal.ts                                     # Bun lane (compiles build/tui-virtual-terminal.js once)
BEND_TUS=4 sh scripts/build-pure.sh tests/tui-virtual-terminal.bend build/tui-virtual-terminal
TUI_RUNNER=build/tui-virtual-terminal bun tests/tui_virtual_terminal.ts   # native
```

Ported so far, all cases: `tui-shrink`, `overlay-short-content`, `tui-overlay-style-leak`, `overlay-options` and `overlay-non-capturing`. Partial: `tui-render`, 25 of 28 tests: resize handling, content shrinkage, differential rendering, Kitty image cleanup and bounded output. The Kitty cases build their image lines and expected sequences with upstream's `Image` and Kitty encoders, as test data; the native renderer places them. In the bounded-output cases the fixture's cursor-visibility entries are left out, as upstream's recording terminal does not record `hideCursor()` as a write. Scripts larger than one command-line argument go through a file (`@path`). Render scheduling, debug-redraw logging and the crash dump are not ported yet.

`overlay-non-capturing` exercises the overlay handle API that `tui-base.bend` exposes as upstream's `OverlayHandle` methods: `focusOverlay`, `unfocusOverlay` (the optional `OverlayUnfocusOptions` is `Maybe<Maybe<ComponentId>>`: omitted, or an explicit target that may be null), `setOverlayHidden`, `isOverlayFocused` and `overlayRemoved` (`hide`). Like `addOverlay`, they are pure transitions; `applyOverlayChange` runs their focus assignments through the components' `setFocused`, in source order, as upstream sets `focused` synchronously. The test's TUI calls become script operations through a small `Session` in the runner, whose component and handle objects read the report of the current render or check, so upstream's assertions (`editor.focused`, `overlay.inputs`, `handle.isFocused()`) stay as written. Upstream's renderAndFlush is a render; assertions it makes without one are a `check`. Adaptations:

- A test's replacement `handleInput` is a component's scripted reaction: the input is recorded, and the TUI calls it made run when the dispatch returns. Upstream makes them inside handleInput, which the dispatch returns from immediately, so the order of TUI transitions is the same.
- An overlay's `visible: () => flag` option is a boolean the script sets (`setVisible`) where the test assigns the flag. The native TUI receives visibility snapshots (`withVisibility`) instead of calling a predicate.
- The microtask-deferred sub-overlay test's promise and microtask produce a fixed order of TUI calls, which the script makes directly.
- Where upstream's base is a `Container`, its children are the TUI's children; `base.clear()` and `base.addChild(editor)` are `tui.clear()` and `tui.addChild(editor)`, with the same mounting and rendering.
- A removed overlay's handle is inert natively (see `tests/overlays.md`). `isOverlayFocused` answers false for it; upstream compares its component with the focused one. No upstream assertion depends on the difference.
