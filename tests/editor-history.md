# Editor history primitives

`kill-ring.bend` preserves upstream `KillRing`: empty kills do nothing, consecutive kills optionally prepend or append to the newest entry, peek does not consume, and rotation persists across subsequent kills. Entries are newest-first; push/peek are constant-time apart from accumulated text, while rotation is linear as in upstream's array unshift. There is no invented capacity or eviction policy.

`undo-stack.bend` preserves the generic `UndoStack` API with immutable snapshots. Push returns the updated stack; pop returns both the remaining stack and the optional snapshot. Clear returns an empty stack. Native values cannot be modified through another reference, so JavaScript structuredClone is unnecessary. A caller can retain an earlier stack and branch from it safely.

`tests/editor_history_reference.ts` imports the actual pinned upstream classes. `tests/editor_history_check.py` compares every observable state in 159 traces / 20,565 transitions, including forward/backward accumulation, empty input, rotation followed by new kills, Unicode/multiline values, interleaved pushes/pops/clear, retained snapshots, and longer histories. This validates the primitives, not editor key dispatch, undo coalescing, cursor restoration, or the full editor test suite; those remain pending.

```sh
bun build/bend-process-files/bend2/main.ts tests/editor-history.bend -o build/editor-history.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/editor-history.bend build/editor-history
python3 tests/editor_history_check.py -- bun build/editor-history.js
python3 tests/editor_history_check.py -- build/editor-history --threads 1
python3 tests/editor_history_check.py -- build/editor-history --threads 4
```
