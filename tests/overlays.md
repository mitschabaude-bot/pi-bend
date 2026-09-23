# Overlay focus policy

`packages/tui/src/overlays.bend` implements the focus and lifetime policy of pinned pi-mono `46c9de402` TuiBase. A single immutable state owns overlay entries, focus order, the current component and pending focus restoration. Component and overlay IDs express membership without mutable object identity. The renderer supplies resolved visibility predicates and mounted component IDs; transitions return ordered focus assignments plus cursor-hide and render requests. Focus assignments retain source order, including clearing and setting the same focused component.

The policy covers showing, permanent removal, temporary hiding, explicit focus/unfocus, retargeting removed ancestors, noncapturing overlays, blocked restoration while another mounted component owns focus, deferred explicit targets, and input-time reconciliation after visibility changes. An ancestor walk is bounded by stack size plus its base target, avoiding a mutable visited set. Repeating a hidden-state assignment is a complete no-op, including focus order. An unfocus request distinguishes no specified target from an explicitly empty target using a typed optional request; this distinction affects meaningful focus restoration.

`tests/overlays_reference.ts` hash-pins `tui.ts` and extracts the actual focus/overlay methods and input reconciliation block. Only terminal effects, component identities and resolved mounted/visibility inputs are supplied by the harness. It compares full stack/pre-focus state, restoration state, focus order and ordered focus-setter calls after each transition. The corpus includes repeated component IDs, visibility changes, removal, mounting changes and both explicit and implicit unfocus requests.

A permanently removed handle cannot reactivate a component. Upstream's retained `setHidden(false)` closure can steal focus after its entry was removed; native stale handles are inert. Four independently asserted removed-handle operations cover this lifetime correction. This follows the user's instruction to avoid retaining legacy object-lifetime defects.

This is a pure policy milestone, not completed TUI or overlay-suite parity. Geometry, bounds, visibility callback execution, renderer/component adapters and terminal input dispatch are separate integration work. Generic focus/lifetime laws and the original whole-TUI suites remain pending; differential traces do not constitute a proof.

```sh
bun build/bend-process-files/bend2/main.ts tests/overlays.bend -o build/overlays.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/overlays.bend build/overlays
python3 tests/overlays_check.py bun build/overlays.js
python3 tests/overlays_check.py build/overlays --threads 1
python3 tests/overlays_check.py build/overlays --threads 4
```

Validation passes 180 sequences / 10,080 exact source transitions and four removed-handle corrections on Bun and optimized native one/four threads.
