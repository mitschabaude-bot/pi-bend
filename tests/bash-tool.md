# Public Bash tool integration

`bash-tool.bend` exercises the canonical `Bash.createBashTool` / `AgentTool.execute` path with caller-owned callbacks and actual native subprocesses. Two context cases call `invokeWithContext` explicitly because the ordinary tool callback has no session-context argument. `bash_tool_check.py` checks public text/details/update frames and reads the complete spill files before deleting its own artifacts.

Reference contracts come from pinned pi-mono `46c9de402`, `packages/coding-agent/test/tools.test.ts` and the canonical Bash/output-accumulator implementations. Coverage includes command prefixes, spawn-hook overrides/errors, context environment exposure, empty output, split UTF-8, nonzero/null exit, abort/timeout formatting, line/byte truncation, exact persisted bytes, coalesced updates, and retained output callbacks after execution resolves (#5208). Truncated complete lines are joined without a trailing newline, matching upstream truncation behavior; ordinary untruncated output retains it.

Native cases cover real stdout/stderr, `/dev/null` stdin, shell prefixes, signal exits, timeout and abort with partial output, exact missing-cwd errors, invalid timeout/preabort precedence over shell lookup, and 32 tool/process lifecycles in one runtime with stable descriptor counts. The fixture disposes borrowed operation/hook/update callbacks itself after disposing the tool, detecting accidental ownership transfer. Retained callbacks are exercised before tool disposal; invoking them after owner disposal is outside their lifetime.

```sh
BEND_TUS=8 sh scripts/build-pure.sh tests/bash-tool.bend build/bash-tool
python3 tests/bash_tool_check.py native-1 native-4
build/bend-native-toolchain/bend2/main.ts tests/bash-tool.bend -o build/bash-tool.js
python3 tests/bash_tool_check.py bun
```

The native build requires the process, null-stdin, and process-TU effect patches plus the filesystem primitives used by the canonical tool. Native one/four-thread runs pass 40 scenarios each, including both repeated-lifecycle cases. The Bun runner selects injected-operation scenarios because native process spawning remains explicitly unsupported on that backend. Its current run fails on the 60,000-byte single-chunk partial-line case with `bend: memory fault (machine stack overflow?)`; preceding injected cases pass, and later cases were not reached. This is an unresolved backend limitation, not a skipped assertion or a completed Bun parity claim. These are integration regressions, not proofs or a claim that all upstream tools tests are ported. Other platform shells, concurrent active invocations and OS failure injection remain outside this fixture.
