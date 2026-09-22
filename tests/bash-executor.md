# User Bash execution

`packages/coding-agent/src/core/bash-executor.bend` ports pi-mono `46c9de402`, `core/bash-executor.ts`, for user/session/RPC Bash execution. It is distinct from the model-facing Bash tool: nonzero or absent exit codes are returned in `BashResult`, cancellation returns collected output, and `onChunk` receives sanitized text without model-tool update frames or truncation notes. `BashExecutorOptions` contains `onChunk` and `signal`; `BashResult` preserves `output`, `exitCode`, `cancelled`, `truncated` and `fullOutputPath`.

The lifetime API is `createExecutor`, `borrowExecutor`, `executeBashWithOperations(handle,command,cwd,operations,options)`, and `disposeExecutor`. The caller joins invocations and retires injected `onData` aliases before disposing the owner. Completed calls retain only an empty gate and its callback until disposal, so late injected output is a harmless no-op. Operations and `onChunk` callbacks remain caller-owned. `Error` distinguishes execution failure, output failure and both together; checked close errors are not discarded.

One serial gate owns the accumulator and immutable decoder/parser state. Accepted appends queue sanitized chunks under that gate. A single publisher swaps batches and calls user code outside locks; its queue never blocks producers on capacity, so a callback can reenter `onData`. Finalization closes acceptance, flushes UTF8 and pending ANSI, joins publication, empties the gate, persists truncation output and checks file close before returning. A single cancellation observation after publisher join governs persistence and the result. A non-cancelled failed operation flushes callbacks and closes an existing spill but does not create a new line-only spill whose path could not be returned. Deferred observations are consumed before their wake handles are replaced/disposed. There are no timers or throttling in this API.

Input raw-byte count still triggers spilling above 50 KB, even when ANSI removal leaves an empty sanitized file. Only sanitized UTF8 bytes are saved. `Output.createPreservingBom` is an additional accumulator constructor with explicit automatic-spill policy: it keeps an initial encoded U+FEFF when the caller already decoded text. The executor disables automatic spilling and uses its original-byte threshold, then requests persistence for a successful/cancelled truncated result. Normal `Output.create` still strips a real initial input BOM and automatically spills for byte or line overflow; its existing line-only persistence was already correct. The executor first decodes original bytes, so an original BOM disappears while a BOM following a removed ANSI sequence remains text.

Deliberate bug fixes follow the approved native policies:

- Completed invocations ignore late injected output; the source user executor has no acceptance guard and can write after its stream was ended.
- ANSI parser state spans chunks; splitting a control sequence cannot leak its payload or remove unrelated text. Incomplete controls are preserved by the ANSI parser and then undergo the ordinary binary-control sanitizer at EOF.
- EOF flushes incomplete UTF8 to U+FFFD; upstream never flushes its TextDecoder.
- Rolling output uses canonical decoded-byte accounting and does not discard whole arbitrary input chunks based on JavaScript UTF16 length. Changing chunk boundaries does not change retained output.
- Canonical truncation counts 2,000 real lines, consistent with the model Bash regression. An untruncated trailing LF remains unchanged; a truncated tail contains the last 2,000 lines without final LF. Upstream user Bash counts the final empty split item and may return only 1,999 real lines plus LF. Sanitized full-output files preserve every LF.
- File completion is awaited and errors are typed; source `WriteStream.end()` returns before persistence completes and does not reliably surface asynchronous write errors. Temporary files use the accumulator’s exclusive 0600 creation.

The bounded output tail does not bound all transient memory: an unfinished OSC holds its pending payload until its terminator or EOF, and an observer slower than producers can accumulate queued chunks. No arbitrary protocol-length limit was introduced. Owner-scoped late-callback gates use a small amount of memory per completed invocation until owner disposal, without retaining output, scanner payloads or open files.

Validation uses the actual pinned executor as a test-only oracle for 83 cases covering sanitized output, BOM handling, null/nonzero exits, failure and cancellation. Additional cases cover every cut position and bytewise splitting of a mixed UTF8/CSI/OSC stream, EOF replacement, line-only truncation, a 51,201-byte single line crossing the byte cap, 55 KB of ANSI-only input producing an empty persisted file, sanitized full-output bytes, invalid byte rejection, late aliases, and 1,000 callback-reentrant appends. Fault injection checks EIO/EINTR close, simultaneous write/close failure, one close/zero leaked descriptors, and combined operation/open failure. The existing accumulator’s 383-case / 7,742-snapshot oracle checks its unchanged default constructor.

The meaningful `tools.test.ts` assertions “should preserve executeBash sanitization when using local bash operations” and “executeBash should persist full output when truncation happens by line count only” are exercised through real local operations natively (`printf` and `seq 3000`). Hosted Process.spawn is intentionally ENOSYS in the current toolchain, so Bun covers injected execution and file effects; it does not claim those two real-process checks. Windows descendant-handle behavior remains outside this POSIX port.

```sh
build/bend-native-toolchain/bend2/main.ts tests/bash-executor.bend -o build/bash-executor.js
sh scripts/build-pure.sh tests/bash-executor.bend build/bash-executor
python3 tests/bash_executor_check.py --runner build/bash-executor.js
python3 tests/bash_executor_check.py --runner build/bash-executor --threads 1
python3 tests/bash_executor_check.py --runner build/bash-executor --threads 4
```
