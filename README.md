# pi-bend

Bend compiler/runtime defects and performance problems are tracked in [the Bend issue log](docs/bend-issues.md). Missing primitives are implementation work in this project, with design and validation records alongside the code. Workarounds remain open investigations until their causes are understood.

Native Bend port of pi, based on `earendil-works/pi` revision `46c9de402` (0.85.1). The current executable is a bootstrap prototype. A faithful port of the modular libraries, types and APIs is in progress under `packages/`; see [architecture fidelity](docs/architecture.md).

The final libraries and complex dependencies must use pure Bend. The bootstrap executable still uses C adapters for networking and Unicode; replacing them is required work. Pure-Bend numeric foundations are under [packages/runtime](packages/runtime/README.md). JavaScript/TypeScript extension compatibility is intentionally excluded; extensions will use Bend.

The existing library code now uses immutable Bend records/lists and explicit updates; the JavaScript object/array compatibility layer has been removed. Structural tool equality and immutable event snapshots are approved adaptations. The full port has resumed; see [native cleanup](docs/native-bend.md).

See [docs/parity.md](docs/parity.md) for the implementation and validation status. Credentials remain in the existing private `~/.pi/agent/auth.json`; never copy credentials into this repository.

Upstream test parity is tracked in [tests/UPSTREAM.md](tests/UPSTREAM.md) and a source-hashed inventory. Unported and partially ported suites remain explicit; passing local smoke tests does not imply full compatibility. The pinned Agent suite now has all 27 named cases ported and passing on one/four threads; this does not establish complete Agent API or provider parity. All 16 public mutable configuration fields have native getter/setter accessors, with supplemental upstream comparisons for capture and replacement behavior. The shared provider transcript transform is assembled, with all four named Copilot migration tests ported; context estimation and shared request-option construction are also ported, including both original context-estimation tests. Complete provider implementations and transport integration remain pending. Native cleartext HTTP is now connected to the canonical Responses assistant processor; [scope and validation](docs/openai-http-reader.md) distinguish that integration from a complete authenticated provider. The [HTTP status boundary](docs/provider-http-response.md) now transfers successful response owners into the existing retry loop and retires failed diagnostic bodies before retry handling.

## Laws and proofs

Generic behavioral contracts live in [LAWS.bend](LAWS.bend), with machine-checked implementations in [PROOF.bend](PROOF.bend). Run `bend PROOF.bend` as the proof gate, or `python3 scripts/check-proofs.py` to also check rejection of open obligations and well-typed broken implementations. The current gate checks 245 public laws and 59 supporting lemmas, with 148 typed mutations rejected. [Proof coverage](docs/laws.md) distinguishes these guarantees from remaining agent, IO and runtime work. Differential, integration and performance tests remain complementary.

## Build and test

Requires Bend 2.0.4, Bun for the Bend compiler, Clang, Python 3 for build/test scripts, libcurl, and ICU development libraries (`icu-uc` and `icu-i18n` via pkg-config). The resulting executable uses no JavaScript runtime.

Canonical library tests currently use Bend 2.0.7 with the explicit [compiler patches](patches/README.md) for shared imports, channel identity and exact monotonic clock ticks. Their pure build path does not link the bootstrap's libcurl/ICU adapters.

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
