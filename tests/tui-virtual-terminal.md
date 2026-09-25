# Upstream TUI suites on a virtual terminal

`tests/tui-virtual-terminal.bend` drives the native TUI (`tui-base` composition, overlays, and the main-screen planner that `tui-process` uses) through a JSON script of operations. It prints each render's ordered terminal writes. `tests/tui_virtual_terminal.ts` replays them into upstream's own `VirtualTerminal` (xterm headless, from the pinned pi-mono checkout) and applies each upstream test's assertions under its original suite and test name. The oracle is test-only.

```sh
bun tests/tui_virtual_terminal.ts                                     # Bun lane
BEND_TUS=4 sh scripts/build-pure.sh tests/tui-virtual-terminal.bend build/tui-virtual-terminal
TUI_RUNNER=build/tui-virtual-terminal bun tests/tui_virtual_terminal.ts   # native
```

Ported so far, all cases: `tui-shrink`, `overlay-short-content`, `tui-overlay-style-leak` and `overlay-options`. Partial: `tui-render`, 16 of 26 tests (resize handling, content shrinkage, differential rendering). Its render scheduling, debug and crash logging, bounded output and Kitty image tests are not ported yet; `tests/tui-main-screen-differential.py` covers bounded output and Kitty reservations at the effect level. Porting `overlay-options` needed upstream's `TUI.hideOverlay()` in `tui-base.bend` (`hideOverlay`: remove the overlay shown last, visible or not). Adaptation: upstream components are TypeScript objects with a `render()` method; here each component renders a fixed list of lines held in a `Ref`, which a script can replace (`set`). That is what these suites' components do; a line can also fill the render width, and the fixture reports the width each component was last asked to render at (upstream's `requestedWidth`). Native overlay margins are `Nat`, so the negative-margin case clamps where options become an `OverlayGeometry`; upstream clamps inside layout, and the assertion is upstream's. Upstream renders on `requestRender`; here the script says when to render and at which size.
