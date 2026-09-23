# Native overlay composition

`packages/tui/src/tui.bend` ports `compositeTuiLine` from pi-mono `46c9de402`. It composes strict cell slices, pads gaps left by intersected wide graphemes, resets SGR/hyperlink state between segments, and clips the result to the viewport. Dimensions use native nonnegative `Nat` values. Image lines containing Kitty or iTerm2 payload markers are preserved unchanged, using the corresponding public recognizer in `terminal-image.bend`; image encoding, capabilities and transport are still pending.

The reference runner hash-checks the original TUI, image, utility and regression sources. It executes all four original overlay-CJK regression bodies, captures both compositor calls, and compares their full output with Bend. The first two helper-only assertions are covered separately by the ANSI layout fixture. An additional 609 exact comparisons cover ASCII, CJK, combining marks, emoji, regional indicators, ANSI styles, hyperlinks, tabs, empty/zero-width inputs, image payloads with and without cursor prefixes, and overlays extending beyond the viewport.

Bun and native one/four threads pass the complete fixture. This is evidence for the pure line compositor, not for interactive TUI rendering, overlay placement, differential terminal writes or mouse dispatch, which remain pending.

```sh
bun build/bend-process-files/bend2/main.ts tests/tui-composite.bend -o build/tui-composite.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/tui-composite.bend build/tui-composite
python3 tests/tui_composite_check.py
```
