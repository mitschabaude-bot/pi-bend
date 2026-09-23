# TUI frame preparation

`tests/tui-frame.bend` validates `Tui.applyLineResets` and `Tui.extractCursorPosition` against their actual hash-pinned upstream `TuiBase` methods at `46c9de402`. The source oracle extracts and transpiles those methods plus the exact marker/reset constants, and uses upstream image detection and Unicode/ANSI utilities. The native fixture observes returned immutable `CursorFrame{lines,cursor}` values instead of source array mutation; row and column are natural-number terminal coordinates.

Two relevant original normalization tests execute with their assertions unchanged: “normalizes Thai and Lao AM vowels only for terminal output” and “keeps tabs inside terminal control sequences byte-identical.” Their normalize/width calls are routed through actual frame preparation, producing eleven native-replayed traces. No upstream test suite is marked fully ported by this focused fixture.

Another 408 exact comparisons cover absent/multiple markers, first marker within the lowest visible marked row, viewport exclusion and zero height, untouched markers on other rows, empty frames/lines, Unicode/ANSI cursor widths, Thai/Lao AM normalization, visible tab expansion, control-string payload preservation, reset suffixes and already-reset lines. Kitty/iTerm image lines remain byte-identical during reset preparation, including embedded visible-looking tabs/vowels and text/control prefixes. Cursor extraction still strips its selected marker when it follows an image line. Long cases include 10,000-character lines with/without markers and a 1,002-line scrollback frame.

Four cursor expectations separately exercise the existing approved complete-CSI scanner correction from `tests/ansi-utils.md`: `ESC[2A` followed by a complete Kitty APC or iTerm OSC has zero visible columns before its cursor marker. The legacy source scanner exposes payload text while seeking an overly restricted CSI final byte; native complete control sequences correctly contribute zero width. Independent zero-column expectations replace only those four cursor columns. Image bytes and every other field continue to compare exactly. No new production defect was found.

Bun and optimized native with one/four threads pass the focused tests. This establishes frame preparation behavior only; terminal writes, render scheduling, focus, overlay integration and the full TUI lifecycle remain separate contracts.

```sh
bun "$BEND" tests/tui-frame.bend -o build/tui-frame.js
BEND="$BEND" BEND_TUS=8 sh scripts/build-pure.sh tests/tui-frame.bend build/tui-frame
python3 tests/tui_frame_check.py
```

The source oracle uses the existing `build/input-reference/node_modules/get-east-asian-width` test dependency. `--prefix` and positional backend names select separate artifacts. The parent agent owns the production TUI implementation; this handoff changes only focused fixture/oracle/checker/documentation files.
