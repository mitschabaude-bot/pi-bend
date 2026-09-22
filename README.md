# pi-bend

Bend compiler/runtime defects and performance problems are tracked in [the Bend issue log](docs/bend-issues.md). Missing primitives are implementation work in this project, with design and validation records alongside the code. Workarounds remain open investigations until their causes are understood.

Native Bend port of pi, based on `earendil-works/pi` revision `46c9de402` (0.85.1). The modular libraries under `packages/` now carry pi's print mode end to end: `BEND_TUS=8 sh scripts/build-pure.sh packages/coding-agent/src/main.bend build/pi-cli` builds the entry point, and `./build/pi-cli -- -p "prompt"` (or `--mode json`) runs the agent loop with the public read/bash/edit/write tools against the OpenAI Responses or Codex Responses APIs using pi's `auth.json` and environment keys. Interactive/RPC modes, sessions, extensions and skills are not ported yet; `src/` remains the bootstrap prototype until they are. See [architecture fidelity](docs/architecture.md) and the [parity record](docs/parity.md).

The final libraries and complex dependencies must use pure Bend. The bootstrap executable still uses C adapters for networking and Unicode; replacing them is required work. Pure-Bend numeric foundations are under [packages/runtime](packages/runtime/README.md). JavaScript/TypeScript extension compatibility is intentionally excluded; extensions will use Bend.

The existing library code now uses immutable Bend records/lists and explicit updates; the JavaScript object/array compatibility layer has been removed. Structural tool equality and immutable event snapshots are approved adaptations. The full port has resumed; see [native cleanup](docs/native-bend.md).

See [docs/parity.md](docs/parity.md) for the implementation and validation status. Credentials remain in the existing private `~/.pi/agent/auth.json`; never copy credentials into this repository.

Upstream test parity is tracked in [tests/UPSTREAM.md](tests/UPSTREAM.md) and a source-hashed inventory. Unported and partially ported suites remain explicit; passing local smoke tests does not imply full compatibility. The pinned Agent suite now has all 27 named cases ported and passing on one/four threads; this does not establish complete Agent API or provider parity. All 16 public mutable configuration fields have native getter/setter accessors, with supplemental upstream comparisons for capture and replacement behavior. The shared provider transcript transform is assembled, with all four named Copilot migration tests ported; context estimation and shared request-option construction are also ported, including both original context-estimation tests. Complete provider implementations and transport integration remain pending. Native cleartext HTTP is now connected to the canonical Responses assistant processor; [scope and validation](docs/openai-responses.md) distinguish that integration from a complete authenticated provider. The [HTTP status boundary](docs/provider-retry.md) now transfers successful response owners into the existing retry loop and retires failed diagnostic bodies before retry handling. [Typed OpenAI errors](docs/openai-responses.md) now connect those diagnostics to pi's error normalization.

## Laws and proofs

Generic behavioral contracts live in [LAWS.bend](LAWS.bend), with machine-checked implementations in [PROOF.bend](PROOF.bend). `python3 scripts/check-proofs.py` checks the full proof root with the installed native toolchain and audits the exact set of unsafe source declarations. The gate currently proves 502 laws across 39 law files, one per constrained module; the [coverage summary](docs/laws.md#coverage-summary) lists them and distinguishes these guarantees from remaining agent, IO and runtime work. Differential, integration and performance tests remain complementary. Agents sharing this checkout coordinate in [AGENT-LOG.md](AGENT-LOG.md).

## Build and test

Requires Bend 2.0.4, Bun for the Bend compiler, Clang, Python 3 for build/test scripts, libcurl, and ICU development libraries (`icu-uc` and `icu-i18n` via pkg-config). The resulting executable uses no JavaScript runtime.

Canonical library tests currently use Bend 2.0.7 with the explicit [compiler patches](patches/README.md) for shared imports, channel identity and exact monotonic clock ticks. Their pure build path does not link the bootstrap's libcurl/ICU adapters. `scripts/build-pure.sh` honours `PI_BEND_OPT` (Clang optimisation, `-O1` by default; `-O0` for development iterations) and `BEND_TUS` (compile the generated C as that many translation units in parallel; the compiler reads the same variable when it emits).

```sh
sh scripts/setup.sh
sh scripts/build.sh
build/pi-bend --no-session -p 'Read this project and explain it'
sh scripts/test.sh
sh scripts/build.sh tests/tool_runner.bend build/test-tools
python3 tests/tools_test.py
python3 tests/agent_fixture.py
```

Current implementation: native print-mode agent loop with OpenAI Codex OAuth, streaming responses, bounded retries, read/write/exact-edit/bash tools, and persisted sessions that can be resumed with `--session <file>`. Native sessions use a separate `~/.pi-bend` directory while upstream session compatibility is developed. Interactive terminal parity, additional providers, and Bend extensions are still in progress. The initial tool implementations are tested but do not yet match every upstream edge case.

The native [OpenAI Responses provider](docs/openai-responses.md) is now five modules under `packages/ai/src/api` plus `packages/runtime/src/fetch.bend`: request preparation, the native client (headers, URL, API errors, one attempt), SSE dispatch, stream processing and the provider lifecycle with pi's retry policy. It runs over native TLS 1.3 and has completed real OpenAI requests through the modular agent loop and canonical write tool. Local HTTPS fixtures verify transcript replay, tool validation, filesystem results and terminal provider failure. Complete provider parity, authentication flows beyond the tested API-key path, the remaining providers and coding-agent CLI integration are unfinished.

Pure coding-tool edit matching/application now lives in `packages/coding-agent/src/core/tools/edit-diff.bend`: original-snapshot multi-edits, exact/fuzzy uniqueness, overlap and no-change errors, LF normalization, and preservation of untouched original lines. NFKC uses a separate generated Unicode17 table and the existing pure normalization algorithm; canonical-only imports do not load the compatibility table. `tests/edit_diff_check.py` invokes the pinned upstream pure source directly, and `tests/unicode_nfkc_check.py` checks Unicode conformance. Positions count native characters, and typed errors are rendered with `errorMessage(error,path,totalEdits)`. Empty fuzzy needles are rejected instead of allowing incidental zero-width edits; exact whitespace needles use literal occurrence counts. For example, upstream rejects replacing the single space in `a b` as two occurrences because it counts `split("")`, while Bend performs that unique edit; upstream can insert at offset zero when a missing whitespace needle normalizes to empty, while Bend reports not found. No pinned named test asserts those artifacts. Edit filesystem/cancellation integration and diff/patch rendering remain pending; no additional edit laws are claimed by these runtime tests.
