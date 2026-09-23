# Terminal color replies

`packages/tui/src/terminal-colors.bend` ports `RgbColor`, `TerminalColorScheme`, OSC 11 framing/color decoding and repeated color-scheme reports from pi-mono `46c9de402`. Native `Maybe` and typed `Dark`/`Light` values replace undefined/string unions. Framing remains independent of decoding so future TUI input dispatch can consume a complete but unparseable reply. Scheme reports select the final report and reject unrelated input.

RGB parsing preserves six/twelve-digit hash colors, case-insensitive rgb/rgba prefixes, bare channel triples, mixed channel widths, whitespace normalization, BEL/ST terminators and exact nearest-integer scaling. The one-to-four-digit channel bound follows the [Xlib RGB device syntax](https://www.x.org/archive/X11R7.6/doc/libX11/specs/libX11/libX11.pdf). Oversized channels, surplus fields, invalid alpha and trailing input are rejected instead of recreating permissive JS parsing or NaN values. A valid fourth rgba channel is validated but not returned, matching the RGB API. The regex end-anchor's acceptance of a trailing newline is deliberately corrected. These malformed-input corrections follow the user's approved strict parsing policy.

The source-hash-checked reference executes the four actual pure parser test bodies and replays their calls. Generated inputs cover variable channel widths, hash colors, prefixes, whitespace, terminators and concatenated scheme reports. All 1,010 source comparisons, six separate correction cases and two long-input scans pass on Bun and optimized native one/four. Production parsing is entirely Bend; Node supplies only the reference. The five TUI query lifecycle, timeout and dispatch tests remain pending until the TUI owner is implemented; this suite is partial.

```sh
bun build/bend-process-files/bend2/main.ts tests/terminal-colors.bend -o build/terminal-colors.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/terminal-colors.bend build/terminal-colors
python3 tests/terminal_colors_check.py bun native-1 native-4
```
