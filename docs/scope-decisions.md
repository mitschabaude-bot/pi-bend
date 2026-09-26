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
  `extension-factory-cache`: jiti imports and the module cache).

- **Windows-only behaviour** (`6596-taskkill-enoent`, `bash-close-hang-windows`,
  `powershell-tool`, 2026-09-26): the coordinator excludes the Windows process
  and PowerShell paths (taskkill, inherited Windows stdio handles, the
  PowerShell tool); the port targets POSIX hosts.
- **Node SEA extension loading** (`8237-node-sea-extension-loading`,
  2026-09-26): it checks jiti and bundled virtual modules in a Node single
  executable; native extensions are compiled Bend.

## Changed

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
