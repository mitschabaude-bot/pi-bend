# Scope decisions

What the port deliberately leaves out, or changes, relative to pi-mono
v0.87.1 (f07218c4d), with the user's decision behind each. Suites of excluded
code carry the status `excluded` in `tests/upstream-inventory.json`, with a
note pointing here. Everything not listed here is in scope.

## Excluded

- **llama.cpp support** (2026-09-26). Gregor explicitly excludes the built-in llama provider, `/login llama.cpp`, `/llama` model management and its Hugging Face download integration. The already committed native client/provider libraries and their tests may remain, but completing or integrating them is outside the port scope.
- **Experimental server stack** (2026-09-26). Upstream's experimental
  services are only reachable with `PI_EXPERIMENTAL=1`: the agent harness
  (`packages/agent/src/harness`, including `pico3`), `chord`, `client`,
  `server`, `protocol`, `durable`, `evals`, `session-backends`, and the
  `experimental/` modules of `coding-agent` that build on them (about 40,000
  lines). The ported harness utility `harness/utils/truncate` stays, as
  other modules use it.
- **Cloudflare Workers AI binding** (`cloudflare-ai-binding`, 2026-09-26). It
  wraps the `env.AI` binding that only exists inside a Cloudflare Workers
  runtime, so the native CLI has nothing to call it with. The Cloudflare
  Workers AI and AI Gateway HTTP providers are ported.
- **Telemetry** (2026-09-25): install telemetry and its options are pi's
  release tracking, not the fork's.
- **`/bug`** (2026-09-25): it reports to upstream pi's tracker; the hint that
  advertises it is excluded with it.
- **First-time setup** (`first-time-setup`, 2026-09-26): upstream runs it only
  with `PI_EXPERIMENTAL` and its main step is the analytics opt-in, so it
  falls under the experimental stack and telemetry decisions.
- **Bun sandbox environment restore** (`restore-sandbox-env`, 2026-09-26): it
  works around a defect of Bun-compiled binaries; a native binary has none.
- **Node native addons** (`native-module-path`, `native-platform`,
  `native-clipboard-linux`, 2026-09-26): upstream loads platform addons from
  Node; a native binary loads none. Clipboard images come from clipboard
  commands (`utils/clipboard-image.bend`). `regression-sigwinch-kill-eacces`
  guards upstream's self-signalling resize path, which the native terminal
  does not have (it reads the size on every resize signal).
- **Self-update** (`config.test.ts`'s install detection and `pi update`
  of pi itself, 2026-09-27): pi-bend is built from source; revisit if it is
  ever distributed.
- **Version check against pi.dev** (2026-09-27): it reports upstream pi's
  releases, which say nothing about pi-bend.
- **macOS and Windows clipboard images** (2026-09-27): upstream reads them
  through its Node addon; not needed for now (see Node native addons).
- **JavaScript/TypeScript extensions** (AGENTS.md): extensions are native
  Bend; upstream's extension loading, bundling and Node SEA behaviour have no
  counterpart (`9540-extension-loader-lazy`,
  `extension-factory-cache`: jiti imports and the module cache;
  `extensions-discovery`: .ts/.js file and package discovery).

- **Windows-only behaviour** (`6596-taskkill-enoent`, `bash-close-hang-windows`,
  `powershell-tool`, 2026-09-26): the coordinator excludes the Windows process
  and PowerShell paths (taskkill, inherited Windows stdio handles, the
  PowerShell tool); the port targets POSIX hosts.
- **Node SEA extension loading** (`8237-node-sea-extension-loading`,
  2026-09-26): it checks jiti and bundled virtual modules in a Node single
  executable; native extensions are compiled Bend.

## Changed

- **Malformed resume-search regex** (2026-09-28): pi silently returns no matches for an empty or invalid `re:` pattern. pi-bend also returns no matches but displays a parsing error, following Gregor's preference to reject invalid input explicitly.
- **Provider SDK headers**: no `x-stainless-*` headers are sent (2026-09-25).
- **Attribution headers** name pi-bend and are off by default (2026-09-25).
- **Documentation** is ported in spirit: the model is never pointed at
  TypeScript extension documentation (2026-09-25).
- **Worker threads**: the default thread count is decided when the binary is
  built (`BEND_DEFAULT_THREADS`, 2026-09-25).
- **`/share`** is ported (2026-09-25).
- **Crash log** (2026-09-27): ported, without the notice that points to
  `/bug` (excluded).
- **Remote model catalog** (pi.dev, 2026-09-27): kept; requests identify as
  pi-bend rather than pi.

## Native value and error semantics

These are approved behavior and API choices, not implementation-completion claims.

- **Immutable values and explicit updates** (2026-09-18): typed records, optional fields and returned updates replace JavaScript reflection, prototypes, symbols, sparse arrays and object identity. Dictionaries retain insertion order without numeric-key sorting; ordinary property names have no special behavior. Hooks return argument/context updates, and cost calculation returns a value rather than mutating an alias. The before_provider_headers handler returns an optional replacement header record; a failed handler leaves the last successful record intact.
- **Structural tool equality** (2026-09-18): dictionary field order does not affect declaration equality; list order and values do. Reordering schema fields alone does not cause a tool redefinition or provider fallback.
- **Signed zero** (2026-09-18): `0` and `-0` compare equal, including in nested values. Schema `uniqueItems` rejects `[0, -0]`.
- **Immutable event snapshots** (2026-09-18): a retained event keeps the content it had when emitted; subsequent events carry subsequent values.
- **Failed asynchronous agent runs** (2026-09-18): close the event stream and return a typed error from the run result. Do not leave the stream unfinished or synthesize an `agent_end` event for a failed run.
- **Bounded SSE diagnostics** (2026-09-19): clear diagnostic lines at each empty block rather than retaining comments and unknown fields indefinitely across heartbeat blocks. Preserve event names, data and emission behavior.
- **Invalid input and dependency bugs** (2026-09-20): preserve meaningful contracts and valid-input behavior, with explicit errors for invalid cases. Do not reproduce permissive parsing accidents or known dependency bugs solely for reference equality. Approved cases include normal boolean JSON-schema semantics, literal schema property names, object/type checks for grammar schemas and Unicode hostname validation. Keep intentional differences explicit in differential checks.
- **Strict resolver configuration** (2026-09-20): recognize whole option names and complete unsigned decimal values, apply numeric caps without wrapping, and reject malformed or unknown options when constructing configuration rather than silently accepting partial values.
