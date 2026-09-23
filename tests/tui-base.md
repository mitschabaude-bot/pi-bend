# TuiBase overlay composition and displayed mouse targets

`tests/tui-base.bend` compares the native `compositeOverlays` and `dispatchMouseToOverlay` with their actual hash-pinned `TuiBase` methods from `pi-mono` revision `46c9de402`. The test-only oracle also uses upstream layout resolution, visibility checks, `dispatchMouseEvent`, image detection and ANSI/Unicode composition helpers. No host callback supplies production behavior.

All 130 cases compare the complete composed frame, displayed overlay bounds, ordered render calls and their widths, mouse callback coordinates/dimensions, and hit/dispatch results. Coverage includes stable equal-order overlays, sorted stacking, hidden/invisible and zero-line overlays, cropping by max height, percentage/anchor placement, short frames and retained scrollback, images, wide/combining text, and style/link controls. The mouse cases cover bounds edges, topmost hits that return no result or explicitly decline handling (without falling through), local handled/focus/capture responses, nested targets, overlay focus ownership, and preservation of a nested focus target when focus was not requested.

For retained-frame cases the source live overlay stack is removed after rendering; its last displayed components still receive mouse events. Native dispatch consumes the immutable displayed `Frame`, whose `OverlayBounds` retains the borrowed component as well as identity and coordinates. The fixture keeps those callbacks alive through dispatch and disposes all render/mouse/invalidation handles afterwards. Omitted boolean response flags are compared as false and absent optional result/targets/render flags as null, matching the native typed model.

Bun and optimized native with one/four threads pass all 130 exact comparisons. No production defect or new scanner-policy correction was required. These are focused differential cases, not a claim that the upstream TUI integration suites are fully ported. Terminal writes, scheduling, focus transitions, live visibility refresh and application-owned rendering remain separate contracts; pure layout, composition and Component behavior retain their existing independent fixtures.

```sh
bun "$BEND" tests/tui-base.bend -o build/tui-base.js
BEND="$BEND" BEND_TUS=8 sh scripts/build-pure.sh tests/tui-base.bend build/tui-base
python3 tests/tui_base_check.py
```

The oracle uses `build/input-reference/node_modules/get-east-asian-width`. Positional backend names and `--prefix` select separate build artifacts. Root owns production `tui-base.bend`; this handoff contains only the focused fixture, oracle, checker and this record.
