# Native settings manager

`packages/coding-agent/src/core/settings-manager.bend` ports the pinned `46c9de402` settings manager as immutable typed settings plus an owned, injectable storage backend. Known fields use `Setting` constructors and typed nested records; unknown JSON fields survive unrelated writes, including unknown package-filter metadata. JSON is confined to configuration boundaries. Numeric counts use `U64`, since Bend's 48-bit `Nat` cannot represent Pi's full safe-integer compaction range.

Pure setters return a new manager and ordered pending writes. `flush`, `reload`, `fromStorage`, and `setProjectTrusted` return the backend together with the manager. Each pending write captures its settings and dirty fields; persistence rereads under the backend lock and replaces only those fields, retaining unrelated external edits. Nested setters mark only their changed nested key. `applyOverrides` affects the effective view until the next saved mutation/reload, matching Pi. Failed reloads retain the previous valid scope, report its path, and prevent writes until a successful reload. Untrusted projects are neither read nor written.

`SettingsStorage(S)` accepts owned backend state, scope, a write-intent boolean, and a pure transaction callback. The callback runs once. `memoryWithLock` is the in-memory backend; `fileWithLock` uses the native proper-lockfile-compatible directory/mtime lease. Explicit write intent avoids creating missing directories on reads and lets a first write create its parent, acquire the lock, then reread before computing the update. This fixes upstream's first-creation lost-update race without replaying an injected callback. Ownership is checked before and after IO, released on every typed outcome, and combined operation/cleanup failures remain typed. `create(cwd, agentDir, options)` takes caller-normalized paths; process environment and path normalization are supplied by the caller rather than hidden in the library. The native CLI is responsible for supplying its configured agent directory.

The named getters/setters cover the pinned preferences, resource lists, global-only project trust, per-model thinking levels, exact model compaction overrides, terminal capabilities, environment fallback, analytics identity, and atomic provider/model updates. HTTP/WebSocket timeout parsing preserves the intentionally supported `disabled` alias, numeric strings, numeric prefixes/exponents, and fractional-millisecond flooring. Image widths retain explicit floor/minimum-one normalization. The resulting settings use typed integer values; serialization writes those normalized values. Environment-sensitive getters accept `Environment` explicitly, including a reusable native `Paths.Environment`.

## Validation

Final source `4cfa3001a34787ecaec2e71dc3b4a96706ef9ef3f8e9bcdc4457d5d91d661939` passed 203 pinned-source comparisons, 60 strict-input checks, analytics UUID creation/persistence/reuse, and 16 real-file cases on Bun and O1 native with explicit `--threads 1` and `--threads 4`. The known-field decoder covers all 51 fields in the pinned `Settings` interface.

Build with a compiler carrying `patches/bend-file-lock-effects.patch` and preceding native filesystem patches:

```sh
BEND=/path/to/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/settings-manager.bend build/settings-manager
BEND=/path/to/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/settings-files.bend build/settings-files
bun /path/to/bend2/main.ts tests/settings-manager.bend -o build/settings-manager.js
bun /path/to/bend2/main.ts tests/settings-files.bend -o build/settings-files.js
python3 tests/settings_manager_check.py -- bun build/settings-manager.js
python3 tests/settings_manager_check.py -- build/settings-manager --threads 1
python3 tests/settings_manager_check.py -- build/settings-manager --threads 4
python3 tests/settings_files_check.py -- bun build/settings-files.js
python3 tests/settings_files_check.py -- build/settings-files --threads 1
python3 tests/settings_files_check.py -- build/settings-files --threads 4
```

`settings_manager_reference.ts` executes the actual pinned settings-manager implementation and its actual HTTP timeout parser. Host code supplies only the reference's process/file imports and deterministic environment. The comparison parses persisted JSON to ignore formatting/property order and normalizes only intentional typed duration/image-width representations. Production does not invoke TypeScript, JavaScript, Python or external commands. The real-file fixture checks no-create reads, global/project persistence, error paths, strict UTF-8, write failure with retained in-memory state, untrusted writes, two concurrent first writers, lock contention and lock retirement. The lock dependency separately verifies proper-lockfile interoperability in both directions, stale recovery, heartbeat compromise and paired cleanup failures; see `file-lock.md`.

The corpus ports meaningful assertions from all three source suites: `settings-manager.test.ts`, `settings-manager-bug.test.ts`, and `settings-manager-compaction.test.ts`. It includes the four bug-suite contracts (external packages/extensions/project edits and same-field local precedence), ordinary/per-model/project compaction fallback, slash-containing model IDs, zero/max-safe counts, preservation of overrides when toggling compaction, defaults and preference persistence, package filters, reload/error draining, trust, terminal capabilities, retry caps, timeout precedence, editor precedence/platform fallback, TUI/fullscreen/output padding/mermaid modes, shell prefix, default tools and tilde path expansion. Additional seeded mutation sequences compare intermediate getters and final persisted contents, rather than merely testing final values.

## Intentional adaptations and remaining integration

Malformed known settings fail at load/override boundaries and enter the existing scoped diagnostic channel. This changes the error timing of `should reject invalid timeout values` and the compaction suite's parameterized invalid-value cases: getters operate on valid typed state instead of throwing later. Invalid entries for an unrelated model are also rejected when loading their scope. The fallback assertions `should default invalid project trust settings to ask`, `falls back to regular for unsupported values`, `should treat unsupported outputPad values as default padding`, and `falls back to streaming for unsupported values` now include a load error, with an empty initial scope or the previous valid reload snapshot retained. Null/wrong-type known fields, duplicate JSON keys, invalid UTF-8, and negative/fractional counts are rejected under the user's explicit malformed-input policy. No JS prototype/property semantics are reproduced.

Setters accept semantic native values: counts are integers, modes are enums, optional removal is `None`, and an absent setting remains distinct from invalid explicit `null`. Integer editor-padding/autocomplete setters retain Pi's clamps; fractional/negative caller values are unrepresentable in their native public signatures. Existing file values for these count fields must be nonnegative integers. File syntax intentionally supporting normalization, such as timeout strings/fractions and image width rounding, is preserved as described above. There is no JavaScript extension adapter.

The canonical manager is implemented here; wiring it into the CLI/session owner is separate work. These fixtures do not claim end-to-end interactive settings UI coverage. IO, migration and differential checks are complementary to the project's laws; no trivial concrete laws or compiler mutation tests were added.

The native C emitter exposed a case-folding name collision during validation: retaining both `getWebsocketConnectTimeoutMs` and upstream's `getWebSocketConnectTimeoutMs` failed with `two names mangle to FID____PACKAGES_CODING_AGENT_SRC_CORE_SETTINGS_MANAGER_GETWEBSOCKETCONNECTTIMEOUTMS`. The unnecessary alternate spelling was removed; only the upstream API remains. No compiler patch was needed.

Root integration rebuilt both fixtures using `build/bend-process-files/bend2/main.ts`, including the shared file-lock effects. The unchanged source above passes the full 203/60/UUID corpus and all 16 real-file checks on Bun and native one/four threads. Inventory entries remain partial pending an assertion-by-assertion audit; these results do not claim CLI settings integration.
