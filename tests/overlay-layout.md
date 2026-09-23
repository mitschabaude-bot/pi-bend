# Native overlay geometry

`resolveOverlayLayout` in `packages/tui/src/tui.bend` ports the pure sizing and positioning calculations from pi-mono `46c9de402`. `OverlayGeometry` is the parsed geometry input: explicit cell/percentage sizes, optional limits/positions, nine anchors, signed offsets and margins. It excludes visibility callbacks, focus and lifecycle state; it is not a replacement for the full upstream `OverlayOptions` API.

Cell counts and margins use `Nat`; offsets use forward/backward magnitudes. Percentages retain binary64 arithmetic and the source's operation order, including its different size-versus-position percentage calculations. Non-finite and negative percentages return a typed error. Negative cell dimensions cannot be expressed by the native type; a future external-options adapter must normalize or reject them explicitly. The test adapter normalizes negative margins to zero as upstream does. Signed anchor intermediates remain signed until offsets are applied and the final margin clamp runs, preserving oversized-overlay placement. Oversized margins can place results outside the physical viewport, as in the source; this resolver does not silently change that behavior.

The runner hash-checks `tui.ts` and executes its actual private resolver and anchor methods without the terminal driver. It compares 1,180 complete layouts across every anchor, default/absolute/percentage sizing, minimum and maximum sizes, fractional/very large percentages, asymmetric/oversized margins, zero-sized terminals, tall overlays and signed offsets. Twelve explicit invalid-percentage inputs check the strict native error. This establishes source comparisons for the pure geometry calculation, not execution of `overlay-options.test.ts`'s interactive rendering/focus/visibility assertions; that suite remains pending.

```sh
bun build/bend-process-files/bend2/main.ts tests/overlay-layout.bend -o build/overlay-layout.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/overlay-layout.bend build/overlay-layout
python3 tests/overlay_layout_check.py
```

Validation: the final readable implementation passes all 1,180 source comparisons and 12 invalid-percentage checks on Bun and optimized native explicit one/four threads, using the unchanged shared compiler.
