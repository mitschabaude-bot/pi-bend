# Immutable in-memory session manager

`packages/coding-agent/src/core/session-manager.bend` now implements the in-memory append, branch, label, tree and fork operations from pinned Pi `46c9de402`. It extends the existing typed entry/context layer in the same module. Session persistence, JSON codecs, filesystem discovery/reload/migration, and restoration of externally supplied entry collections remain pending; this is not full session-manager parity.

## API and representation

`inMemory(header)` creates a checked immutable `SessionManager<D,T,C>`. Each append receives `EntryStamp{id,timestamp}` and returns `Result<Error,SessionManager>`; callers already know the supplied ID. `branch`, `resetLeaf`, `branchWithSummary`, `newSession` and `createBranchedSession` return replacement state. Queries preserve the meaningful upstream names. `sessionContext` and `sessionContextEntries` are the state-taking equivalents of upstream methods, while the existing `buildSessionContext`/`buildContextEntries` functions retain their entry-list APIs. `Latest` in `getBranch` means the selected leaf; an unknown explicit ID returns an empty path, as upstream does. This intentionally differs from the older standalone context helper's missing-leaf fallback.

History is a reversed immutable list with a persistent ID index. Branch selection never removes history. Resolved labels use a persistent index plus insertion-order tickets: replacing retains position, clearing and reinserting moves to the end. Forking reconnects the retained path after removing label entries, repairs compaction references to removed labels, and recreates only labels targeting the retained non-label path, preserving their original timestamps. The caller supplies a fresh session stamp and exactly one ID per recreated label, in resolved-label order. Reused/empty entry IDs and incorrect label-ID counts reject atomically; the caller retains the original state.

`getTree` assembles subtrees bottom-up using the append order's parent-before-child invariant. It avoids recursive traversal of deep trees, sorts children stably by parsed timestamp, and retains root insertion order. Ordinary append/index operations do not rescan history; tree assembly costs O(n + sum(k log k)) map operations/comparisons, where k is each parent's child count. The state is intended to be created and changed through these checked functions; a future external-entry loader must validate/topologically order imported entries rather than directly constructing this record.

All supplied timestamps use the existing strict zoned ISO/Gregorian parser, including numeric offsets. Four-digit years remain the existing calendar limitation. IDs are supplied explicitly rather than generated inside pure transitions; their nonempty uniqueness is checked. Native effects may supply UUIDs and formatted wall-clock timestamps at the boundary. Append rejects branch/compaction summary messages in the ordinary message API, preserving upstream's typed restriction to top-level summary entries. No mutable JS identity or reflective representation is recreated.

## Validation

`session_state_reference.ts` executes the actual `tree-traversal.test.ts` and `labels.test.ts` assertions through a wrapper around the actual pinned `SessionManager`. It extracts only the two pure fixture constructors from the original utilities source to avoid loading unrelated authentication/provider catalogs. It records each mutation and subsequent state; it does not replace expected values with an independently reimplemented manager. `session_state_check.py` replays the supplied stamps and operations in Bend and compares parent links, entry payloads, summary usage/details/fromHook, system-compaction snapshots, selected leaf, branch paths, child order, resolved tree labels/timestamps, session name and context after each transition.

The port covers **37 original tests** and **155 transition snapshots**, including additional cases for cleared/reinserted label order, root summaries, reset roots, session-name sanitization, system snapshots, compaction references to removed labels, and stable chronological child ordering. Separate checks cover six atomic rejection paths (duplicate/empty IDs, invalid dates, and missing/duplicate/excess fork-label IDs), recreated IDs equal to removed label targets, and **10,001-node wide and deep trees**. The existing session-context fixture is updated only for the extended error union and import-safe local names.

All state checks passed on Bun and O1 native with explicit `--threads 1` and `--threads 4`. The existing context regression also passed again on Bun: 505 comparisons, 156 raw paths, malformed graph/date errors and its 10,000-entry context.

Three named original filesystem tests remain pending: “does not duplicate entries when forking from first user message”, “preserves tool and summary usage across a file-backed reload”, and “writes file immediately when forking from a point with assistant messages”. No law coverage is claimed for this milestone; the substantial behavioral checks are original-source differential comparisons and large-tree execution, not concrete examples relabeled as proofs.

```sh
build/bend-native-toolchain/bend2/main.ts tests/session-state.bend -o build/session-state.js
sh scripts/build-pure.sh tests/session-state.bend build/session-state
python3 tests/session_state_check.py --runner build/session-state.js
python3 tests/session_state_check.py --runner build/session-state --threads 1
python3 tests/session_state_check.py --runner build/session-state --threads 4
```
