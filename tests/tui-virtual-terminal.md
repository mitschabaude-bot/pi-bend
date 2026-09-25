# Upstream TUI suites on a virtual terminal

`tests/tui-virtual-terminal.bend` drives the native TUI (`tui-base` composition, overlays, and the main-screen planner that `tui-process` uses) through a JSON script of operations. It prints each render's ordered terminal writes. `tests/tui_virtual_terminal.ts` replays them into upstream's own `VirtualTerminal` (xterm headless, from the pinned pi-mono checkout) and applies each upstream test's assertions under its original suite and test name. The oracle is test-only.

```sh
bun tests/tui_virtual_terminal.ts                                     # Bun lane
BEND_TUS=4 sh scripts/build-pure.sh tests/tui-virtual-terminal.bend build/tui-virtual-terminal
TUI_RUNNER=build/tui-virtual-terminal bun tests/tui_virtual_terminal.ts   # native
```

Ported so far: `tui-shrink`, `overlay-short-content` and `tui-overlay-style-leak`, all cases. Adaptation: upstream components are TypeScript objects with a `render()` method; here each component renders a fixed list of lines held in a `Ref`, which a script can replace (`set`). That is what these suites' components do. Upstream renders on `requestRender`; here the script says when to render and at which size.
