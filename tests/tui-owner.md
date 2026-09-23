# TuiBase owner frame and core input callbacks

`tests/tui-owner.bend` invokes the production owner with real Component render, focus and input callbacks. It checks that root children render before the overlay at the expected widths, `renderRoot` leaves the old displayed bound (id 9) in place, and `commitFrame` publishes the new bound (id 3). It then sends a Kitty key release, a normal key, and input after the focused overlay becomes hidden. The release is filtered; the normal key reports an immediate render request; hidden-overlay input calls focus callbacks in source order (`F3-`, `F1+`) before the base component receives input. The frame remains the last committed frame throughout input processing.

The checker derives the composed frame from the hash-pinned upstream `TuiBase` composition oracle, verifies the pinned source reset sequence, and executes the upstream `isOverlayVisible`, `compositeOverlays`, `handleTerminalInput`, `setFocusInternal` and `getVisibleOverlayFocusRestore` methods with real `keys.ts` release detection. It compares the callback order and immediate-render result. This is core dispatch after the source's middleware, cell-size and debug preprocessing; those stages are separate contracts. Bun and optimized native one/four threads pass the current owner scenario.

Dynamic visibility is pending. Upstream invokes `options.visible(columns, rows)` once for this overlay during each render and once for visible focused-overlay input. When the predicate becomes false, the input path calls it three times before `F3-`, `F1+`, `I1` and the immediate render request. The source oracle records the exact order in `tests/tui_owner_visibility_reference.ts`. The current Bend owner stores a static `O.State.visible` value and has no predicate refresh before `renderRoot` or `dispatchInput`, so it cannot observe a changed predicate without an explicit visibility update. The proposed explicit snapshot boundary can use these source call counts to decide when to evaluate predicates and then pass the snapshot through `O.setVisibility`.

```sh
/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts tests/tui-owner.bend -o build/tui-owner.js
BEND=/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/tui-owner.bend build/tui-owner
python3 tests/tui_owner_check.py
```

Root owns `packages/tui/src/tui-base.bend`; only this focused fixture, checker, oracle and record belong to this handoff.
