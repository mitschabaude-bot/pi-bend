# Session entry and context layer

`core/session-manager.bend` ports the pure typed entry/path/context portion of Pi `46c9de402`, `core/session-manager.ts`. It includes header/options, all entry variants, file/tree/context/session-info records, checked indexing, parent paths, latest compaction lookup, context entry selection, message projection and settings. Persistence, migration, filesystem discovery, label resolution/tree construction and the `SessionManager` class are not implemented here. The whole session-manager suite remains partial.

A shared `SessionEntryBase` contains identity, parent and timestamp. Entry variants preserve their meaningful fields. `CompactionEntry<C>` is separately nameable because latest-compaction lookup must return that narrower type. The `D/T/C` parameters are the agent's diagnostic/tool/extension payload types; extension data is not represented as generic JSON. Native `AgentMessage` and `core/messages.bend` provide all message payloads.

`LeafSelection` distinguishes latest entry, explicit root and a selected ID. The original tests require falling back to the latest entry when a leaf ID is unknown and stopping a chain at a missing parent; both behaviors remain. Empty IDs and duplicate IDs return typed errors. Following more parents than the checked index contains proves a selected-path cycle and returns `Cycle`, rather than hanging. Unselected disconnected cycles are not traversed. The index uses Base's persistent string map, not repeated linear searches through the session. `buildSessionContext` builds the path once and derives both settings and compacted messages from it.

Compaction selection keeps the latest compaction entry, the retained prefix beginning at `firstKeptEntryId` (excluding older system messages), and the suffix after compaction. Missing kept IDs omit the earlier prefix, as upstream does. Model and thinking settings scan the entire selected path, including entries removed from the resulting context. Assistant messages update the model; later explicit model changes can replace it. Compaction system snapshots precede their summary, hidden custom messages remain in context, empty branch summaries are omitted, and ordinary custom-state/label/session-info entries contribute no messages.

The oracle executes all 16 original `session-manager/build-context.test.ts` cases and captures 37 public calls. Generated trees and focused compaction/system/custom scenarios bring the total to 505 pinned comparisons. The harness additionally checks 156 raw parent paths, duplicate/empty IDs, self/two-node cycles, invalid generated-message timestamps, and an in-core 10,000-message context. Validation passes Bun and optimized native execution with explicit one and four workers.

Generated custom/branch/compaction messages use the existing strict zoned ISO timestamp parser and return `InvalidTimestamp` on invalid input. Plain typed messages are passed through. Missing/null content fields from unvalidated legacy JSON cannot inhabit the native message records; deciding how to reject or normalize those files belongs to the future persistence decoder, not this pure layer. Session-info created/modified dates are native epoch milliseconds. No JavaScript identity/prototype semantics or optional caller-supplied JS maps are emulated; callers that cache the native checked index can use `indexedPath`.

```sh
build/bend-native-toolchain/bend2/main.ts tests/session-context.bend -o build/session-context.js
sh scripts/build-pure.sh tests/session-context.bend build/session-context
python3 tests/session_context_check.py --runner build/session-context.js
python3 tests/session_context_check.py --runner build/session-context --threads 1
python3 tests/session_context_check.py --runner build/session-context --threads 4
```
