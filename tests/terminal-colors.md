# Terminal color replies

`packages/tui/src/terminal-colors.bend` ports `RgbColor`, `TerminalColorScheme`, OSC 11 framing/color decoding and repeated color-scheme reports from pi-mono `46c9de402`. Native `Maybe` and typed `Dark`/`Light` values replace undefined/string unions. Framing remains independent of decoding so future TUI input dispatch can consume a complete but unparseable reply. Scheme reports select the final report and reject unrelated input.

RGB parsing preserves six/twelve-digit hash colors, case-insensitive rgb/rgba prefixes, bare channel triples, mixed channel widths, whitespace normalization, BEL/ST terminators and exact nearest-integer scaling. The one-to-four-digit channel bound follows the [Xlib RGB device syntax](https://www.x.org/archive/X11R7.6/doc/libX11/specs/libX11/libX11.pdf). Oversized channels, surplus fields, invalid alpha and trailing input are rejected instead of recreating permissive JS parsing or NaN values. A valid fourth rgba channel is validated but not returned, matching the RGB API. The regex end-anchor's acceptance of a trailing newline is deliberately corrected. These malformed-input corrections follow the user's approved strict parsing policy.

The source-hash-checked reference executes the four actual pure parser test bodies and replays their calls. Generated inputs cover variable channel widths, hash colors, prefixes, whitespace, terminators and concatenated scheme reports. All 1,010 source comparisons, six separate correction cases and two long-input scans pass on Bun and optimized native one/four. Production parsing is entirely Bend; Node supplies only the reference. The five TUI query tests run separately, below.

```sh
bun build/bend-process-files/bend2/main.ts tests/terminal-colors.bend -o build/terminal-colors.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/terminal-colors.bend build/terminal-colors
python3 tests/terminal_colors_check.py bun native-1 native-4
```

## TUI query lifecycle and input interception

`tests/tui_terminal_colors_check.py` runs the five `TUI.queryTerminalBackgroundColor` tests on the running native TUI through a real PTY (native one/four threads; the hosted runtime cannot acquire a terminal). `tests/tui-terminal-colors.bend` focuses an input recorder, registers an input listener, and starts the background query (`Query.colorQuery`, upstream's `tui.queryTerminalBackgroundColor`) once the TUI is ready; stderr reports each listener call, component input and query result. The cases keep upstream's names and assertions: the query is written and resolves with the parsed reply; a reply is consumed before input listeners and the focused component; an unparseable strict reply is consumed and resolves undefined; ordinary input still reaches the listener and component while a query waits; and a reply arriving after a 1 ms timeout is still consumed.

The native TUI now has upstream's input listeners (`terminal-query.bend`: `addInputListener`, `removeInputListener`, `TuiInputListenerResult{consume,data}`). In `tui-process`, input passes the OSC 11/colour-scheme reply consumers, then the listeners in registration order (a listener may consume the input or replace it; empty remaining input is dropped), then the cell size reply consumer, then dispatch, as upstream `handleTerminalInput`. Registration returns an id used for removal instead of an unsubscribe closure; each input runs the listeners registered when it arrives, called outside the query lock.

```sh
python3 tests/tui_terminal_colors_check.py
```

## Cell size replies

Upstream's `tui-cell-size-input.test.ts` runs through `tests/tui_cell_size_check.py` (real PTY, native one/four threads). At start the TUI writes `CSI 16 t` when the environment's terminal supports images (terminal-image capability detection; the TUI process holds no capability overrides, so an application's `terminal.images` setting does not suppress the query). A whole `ESC [ 6 ; height ; width t` reply is consumed; positive sizes become the cell dimensions (`Query.getCellDimensions`, upstream's `getCellDimensions`), every component is invalidated and a frame requested. Both upstream cases pass in upstream's image-terminal environment (`TERM_PROGRAM=ghostty`): a bare Escape still reaches the focused component, and a reply is consumed while later input is forwarded, leaving 10×20 cells. A supplementary case checks that a terminal without image support is not queried.

```sh
python3 tests/tui_cell_size_check.py
```
