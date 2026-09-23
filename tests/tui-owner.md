# TuiBase owner frame and core input callbacks

`tests/tui-owner.bend` invokes the production owner with real Component render, focus and input callbacks. The test caller evaluates the overlay's visibility once before each render and input operation and supplies it through `withVisibility`. It checks that root children render before the visible overlay at the expected widths, `renderRoot` leaves the old displayed bound (id 9) in place, and `commitFrame` publishes the new bound (id 3). After a visible key release and normal key, the caller supplies a hidden snapshot. The next render omits the overlay and retains the previous displayed bound until commit; the committed frame has no overlay bound. Hidden-overlay input calls focus callbacks in source order (`F3-`, `F1+`) before the base component receives input. The release is filtered and both delivered keys report an immediate render request.

The checker derives the composed frame from the hash-pinned upstream `TuiBase` composition oracle, verifies the pinned source reset sequence, and executes the upstream `isOverlayVisible`, `compositeOverlays`, `handleTerminalInput`, `setFocusInternal` and `getVisibleOverlayFocusRestore` methods with real `keys.ts` release detection. It compares the callback order and immediate-render result. This is core dispatch after the source's middleware, cell-size and debug preprocessing; those stages are separate contracts. Bun and optimized native one/four threads pass the current owner scenario.

The source oracle records the exact predicate call order in `tests/tui_owner_visibility_reference.ts`: upstream calls `options.visible(columns, rows)` once during each render and once for visible focused-overlay input. After the predicate becomes false, its input path calls it three times before `F3-`, `F1+`, `I1` and the immediate render request. The Bend caller intentionally evaluates each dimension-dependent predicate once per operation and passes an immutable snapshot to `withVisibility`; the resulting frame, focus order and input result match upstream while predicate invocation count differs at this pure snapshot boundary. The caller is responsible for supplying fresh snapshots when dimensions or application visibility change.

```sh
/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts tests/tui-owner.bend -o build/tui-owner.js
BEND=/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/tui-owner.bend build/tui-owner
python3 tests/tui_owner_check.py
```

Root owns `packages/tui/src/tui-base.bend`; only this focused fixture, checker, oracle and record belong to this handoff.
