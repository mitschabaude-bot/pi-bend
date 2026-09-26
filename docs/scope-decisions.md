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
- **JavaScript/TypeScript extensions** (AGENTS.md): extensions are native
  Bend; upstream's extension loading, bundling and Node SEA behaviour have no
  counterpart.

## Changed

- **Provider SDK headers**: no `x-stainless-*` headers are sent (2026-09-25).
- **Attribution headers** name pi-bend and are off by default (2026-09-25).
- **Documentation** is ported in spirit: the model is never pointed at
  TypeScript extension documentation (2026-09-25).
- **Worker threads**: the default thread count is decided when the binary is
  built (`BEND_DEFAULT_THREADS`, 2026-09-25).
- **`/share`** is ported (2026-09-25).
