# Bend compiler patches

## One toolchain

Since 2026-09-23 there is exactly one patched compiler: `build/bend-native-toolchain/bend2` in the main checkout, which `scripts/build-pure.sh` and the proof scripts use by default. Other paths that earlier work used (`build/bend-process-files`, `build/bend-system-identity`, and the second checkout's `build/bend-native-toolchain`) are symbolic links to it; the previous copies remain beside them as `*.old-2026-09-23` for a while. It contains every installed patch below plus `bend-process-clock.patch`, `bend-terminal-effects.patch`, `bend-tcp-callback.patch` and the `experimental/system-identity` effect (applied with `scripts/prepare-system-identity-candidate.py`). These additions only add Base declarations and effect files; unrelated fixtures compile to byte-identical C with and without them. New effects are installed into this toolchain after the same checks, not into another copy.

Keep patches minimal and check relevant performance against an otherwise identical baseline before installing them. Correctness tests alone are insufficient. Memory experiments must measure time as well as memory; see the limitations and pending performance work in [the Bend issue log](../docs/bend-issues.md).

`bend-compiler-literal-memory.patch` is installed in both the ordinary Bend 2.0.7 compiler and `build/bend-native-toolchain/bend2`, which the build and proof scripts use by default. Explicit `BEND` overrides remain supported; telemetry and automatic updates remain enabled. The latest full-provider comparison measured **124 seconds/7.29 GiB**, versus 191 seconds/7.47 GiB, with byte-identical C and passing runtime/proof checks. Current compiler work prioritizes speed over further RSS reductions.

The aggregate patch shares immutable literal trees and fieldless constructors without skipping validation, interns only at identical source-span objects, bounds indentation, caches constructor fields/layouts, limits per-definition cache/probe lifetimes, discards unstable emission output before the existing collection points, avoids constructing unused match/telescope result types, and compares layouts directly instead of serializing them. [Investigation history and measurements](../docs/bend-issues.md) preserve the intermediate results and rejected experiments. Historical incremental patches under `experimental/` are not the authoritative installed patch. Small-fixture timings are mixed within milliseconds; shared-host measurements do not establish a universal absence of performance regressions.

`bend-hot-constructor-fields.patch` is installed in both compiler sources. It fixes native memory corruption when sharing a generic constructor such as `Some` makes its concrete record payload reference-counted while that record's reader still treats it as unwrapped. One executable line reuses the existing transitive sharing analysis and fixed-point emission loop. The positive `tests/shared_optional_record.py` regression passes on Bun and native one/four threads. Three unaffected fixtures produce byte-identical C; the full X509 compile median was 12.76 → 11.73 seconds in three alternating pairs. Evidence and hashes record the scope and shared-host uncertainty.

`bend-filesystem-paths.patch` is installed in the ordinary/native toolchains and the isolated cap-hot toolchain. It adds `Directory.ensure` (one directory), `File.realpath_bytes`, and `Directory.current_bytes`; filesystem recursion, UTF-8 validation and file-operation policy stay in Bend. No compiler or runtime-core code changes. `tests/filesystem_paths_check.py` passes on Bun and native one/four threads, including symlinks, malformed path bytes, creation races, permission errors and descriptor retirement after failed writes. Unrelated tool-truncation and shared-optional-record fixtures emit byte-identical C. Three alternating codegen pairs had baseline/candidate medians 0.54/0.55 seconds and 0.40/0.40 seconds; median RSS was 163,324/161,476 KiB and 122,648/124,432 KiB. These shared-host measurements do not establish a universal performance guarantee.

`experimental/bend-tcp-bytes.patch` is an **uninstalled candidate**, adding `TCP.send_bytes` and `TCP.recv_bytes` with the same affine socket/result shape as the text operations and Base's existing byte-list representation. It adds two Base declarations and four effect files; it does not edit the existing text effects, checker, code generator or runtime core. The adapters follow existing TCP scheduling and `File.read_bytes`/list-marshalling patterns. Invalid send elements above 255 return EINVAL before writing any bytes; the contract tests verify this with a valid prefix before an invalid element and with U32 maximum. The basic loopback probe (`BEND=<isolated candidate launcher> python3 tests/tcp_bytes_probe.py`) sends and receives all 256 byte values on one/four native threads and the JS backend. The additional `tests/tcp_bytes_contract.py` checks invalid/empty sends, zero-length and short reads, repeated EOF, socket reuse, connection-reset read errors and subsequent send errors on one/four native threads and JS. The reset sequence uses an acknowledged handshake. Baseline C output is identical for the existing text-TCP and UTF-8 fixtures; initial build-time/RSS comparisons are recorded in the issue log. The Linux `tests/tcp_bytes_backpressure.py <candidate bend2 directory>` test also passes on both backends: scheduler read waiting, injected read EAGAIN retry, actual kernel write EAGAIN/resumption and exact 65,536-byte delivery. It instruments only a temporary copy and does not benchmark that copy. Cancellation interactions, sustained resource behavior and runtime throughput remain pending. The candidate remains uninstalled; these tests are not full acceptance.

`bend-shared-import-namespace.patch` fixes a module-loader issue observed in Bend 2.0.5. A file imported directly and through a sibling package could receive two lexical namespaces when the paths crossed above the entry directory. The loader now reuses a completed file’s established namespace when assigning a local import alias. Active import cycles remain errors. This changes the compiler’s import resolution; it adds no foreign behavior to the Bend executable.

Apply it to the installed compiler source after inspecting compatibility with the installed release:

```sh
patch --forward -p1 -d "$HOME/.bend/current" < patches/bend-shared-import-namespace.patch
python3 tests/module_imports.py
```

`bend-channel-identity.patch` adds the pure primitive `Chan.same(A, left, right)` to Bend 2.0.5. It compares opaque channel handles without reading contents, taking locks, allocating or invoking callbacks. The native backend compares the existing index/generation handle; the JS backend compares the channel object itself. It does not introduce a foreign effect, library adapter or JS dependency into native programs. `Ref.same` and `Callback.same` are pure Bend wrappers over this primitive; callback equality must distinguish separate factories even when their code and captured values match.

```sh
patch --forward -p1 -d "$HOME/.bend/current" < patches/bend-channel-identity.patch
python3 tests/runtime_identity.py
```

Identity tests run native binaries on one and four threads and check the compiler's JS lowering separately. They cover runtime aliases, equal-but-distinct values/callbacks, mutation, non-consuming comparison, channel slot reuse and rejection of different channel element types. Comparing references/callbacks does not extend their lifetime; owners must still retire aliases before disposal.

`bend-monotonic-nanoseconds.patch` adds `IO.monotonicNanoseconds() -> IO(U32 & U32)` to Bend 2.0.5. The native effect calls the runtime's existing monotonic nanosecond reader and returns its high/low words. The JS compiler backend reads `process.hrtime.bigint` and returns the same word representation. This is a small OS clock primitive; origin subtraction, binary64 rounding, units and Event construction are implemented in Bend. It neither changes `IO.now` nor truncates ticks to milliseconds.

```sh
patch --forward -p1 -d "$HOME/.bend/current" < patches/bend-monotonic-nanoseconds.patch
python3 tests/clock_vectors.py
```

The clock tests compare 276 interval vectors bit-for-bit and exercise both primitive backends, monotonic progress, concurrent reads and Event timestamps. The JS test runs in Bun, as required by the existing sleep effect; Node supplies the numeric oracle. The origin is explicitly owned by a runtime `Clock`; canonical application startup must initialize and share it. A separate clock per Event would change the source contract and is not the intended composition.

Eight patches are currently applied locally to Bend 2.0.7, including the static-sum conversion and typed-do binding fixes below. The import, channel identity, monotonic/Unix clock, JS identifier, static-layout and typed-do regression scripts pass on this release. Bend automatic updates remain enabled, so a future release may remove them or implement the changes upstream. The module regression checks both diamond-import orders and cycle rejection; `sh tests/transcript.sh` additionally exercises the real ai/agent/runtime dependency graph. The build script does not silently modify the compiler. The aggregate compiler-memory patch described above is installed.

`bend-unix-milliseconds.patch` adds `IO.unixMilliseconds() -> IO(U32 & U32)`. It returns signed Unix epoch milliseconds as two's-complement high/low words. The native effect reads `CLOCK_REALTIME` and reduces its normalized seconds/nanoseconds pair to integer milliseconds without host floating point. An OS clock failure terminates with an explicit diagnostic. The JS backend uses `Date.now()` and the same word representation. `IO.now` and the monotonic primitive are unchanged. The pure-Bend `date.bend` module handles signed conversion to binary64. This is a small OS primitive, not a foreign Date library.

`bend-js-identifiers.patch` fixes invalid JS emitted for canonical modules such as `f64-decimal.bend`. The compiler now escapes punctuation and Unicode UTF-16 units, including the escape marker itself, instead of substituting only path separators. Distinct paths such as `a-b`, `a_b` and `a$2d$b` remain distinct valid identifiers. This changes only backend symbol spelling, not Bend source names or native production behavior.

```sh
patch --forward -p1 -d "$HOME/.bend/current" < patches/bend-unix-milliseconds.patch
patch --forward -p1 -d "$HOME/.bend/current" < patches/bend-js-identifiers.patch
python3 tests/js_identifiers.py
python3 tests/date_vectors.py
```

Date checks cover 146 signed integer conversion vectors, native one/four-thread readings and the Bun-hosted JS backend. Live readings are bounded by the host wall clock around each process call; they do not assume wall time is monotonic or provide clock-adjustment/timer guarantees. Compiler symbol tests separately cover hyphen, underscore, escape-marker and Unicode paths.

`bend-static-layout.patch` fixes native constant-image emission for nested generic constructors. Field-layout conversion can emit local temporaries even when its inputs are literal constants. The compiler previously checked the inputs' static flags and inserted those local names into global `STAT_IMG`, producing undeclared-identifier C errors. Both boxed and unboxed constructor paths now derive static eligibility from the converted fields, and boxed-node emission propagates that result to its parent. Literal data whose converted fields remain static can still enter the constant image. No production foreign effect or library is added.

```sh
patch --forward -p1 -d "$HOME/.bend/current" < patches/bend-static-layout.patch
python3 tests/static_layout.py
python3 tests/static_layout.py
```

The reduced regression (`tests/static-layout.bend`) was verified to fail native compilation with the unpatched compiler and to pass with the patch on one/four threads; the JS backend also passes. It nests generic data/accessor descriptors with optional fields inside a list. The original property-inspection fixture likewise reproduces the failure before the patch. Shared runtime values, primitive coercion and generic/assistant event-stream regressions pass with the patch applied.


`bend-static-sum-conversion.patch` fixes conversion between native layouts for a statically known algebraic-data variant. Previously, conversion emitted every destination branch and tried to interpret the live success payload as an unrelated error payload while generating an inactive branch. A small generic IO/Result program reproduced the compiler crash. Conversion now selects the known live constructor before converting its fields, preserves destination padding/tag layout, and derives static eligibility from the converted fields. Dynamic sum conversion retains its existing branch handling. This changes compiler code generation, not application semantics or production dependencies.

```sh
patch --forward -p1 -d "$HOME/.bend/current" < patches/bend-static-sum-conversion.patch
python3 tests/static_sum_layout.py
```

The standalone regression covers empty/populated successes, both error variants, nested text/number payloads and subsequent generic IO round trips on one/four native threads and the JS backend. The preceding static-layout regression remains green on both backends. The fix was required by the Responses converter's instantiation of the existing generic message transformer with a structured error type.

`bend-typed-do-shadow.patch` fixes typed `do` bindings that share a name with a module-level function. The parser previously resolved the binding name as a global before deciding whether it introduced a local. Importing a module therefore made a previously valid standalone binding fail at `:`, and `+name` could be mistaken for a quantified datatype. The parser now recognizes a bare typed binding before name resolution, while ordinary expressions follow their existing parsing path. Qualified names remain invalid binding names. This addresses the typed-do part of BEND-012, not all pattern/lambda shadowing concerns.

```sh
patch --forward -p1 -d "$HOME/.bend/current" < patches/bend-typed-do-shadow.patch
python3 tests/typed_do_shadow.py
```

The reduced fixture verifies effectful and pure typed bindings, copyable bindings, nested lexical shadowing, global calls in initializers and tail actions in both standalone and imported forms. Native one/four-thread and JS checks pass; qualified binding names remain rejected. Before the patch, `tests/typed_do_shadow.py --expect-bug` verified standalone success and imported failure. All seven preceding compiler regressions and canonical library types also pass with the fix.

The additive [owned timer experiment](experimental/timer/README.md) is isolated and **not installed**. It adds Base declarations and two new effect files without modifying compiler/scheduler code or existing effects. Core native/Bun lifetime tests and unchanged-output checks pass; race/scaling coverage and performance acceptance remain pending.

`bend-word-literal-arms.patch` (2026-09-22) is installed in `build/bend-native-toolchain/bend2`. It compiles a column of complete `U32` literal patterns (every string character, `case 42:`) into one match arm per literal instead of 32 nested bit matches, which removed the quadratic duplication of default arms recorded under BEND-016/022/023/025. The evidence is in the issue log's BEND-016 resolution entry: the agent test fixture's C shrank from 176.7 MB to 2.8 MB, its emission from 25.4 s to 4.1 s and its Clang time from 294 s to 40 s, with the proof gate and the merge harnesses passing. The ordinary `~/.bend` installation is unchanged.

`bend-layout-cap.patch`, `bend-static-boxed-nodes.patch` and `bend-pass-memos.patch` (2026-09-22, applied in that order after the word-literal arms) are installed in `build/bend-native-toolchain/bend2`. The cap boxes records wider than `BEND_LAY_MAX` (default 32) cells so the real program stays under the byte arity table and emits in 89 s at 3.4 GiB instead of failing after 317 s at 22 GiB; static records boxed into generic fields now stay in the static image, which removed a 6.9 MB table-building function and cut Clang from 685 s to 157 s on the native agent; the memos are two small per-pass caches. Evidence and the runtime benchmark are in the issue log's BEND-010 resolution entry.

`bend-file-mode-close.patch` adds `File.open_mode(path, mode, permissions)` and `File.close_checked(file)` after `bend-filesystem-paths.patch`. Only Base declarations and four OS effect files change; existing primitives and compiler/runtime core stay unchanged. Creation permissions go through the OS umask and do not change existing files. Checked close consumes its affine handle and attempts close exactly once, including on EINTR. The pure Bend filesystem layer chooses 0666, returns close errors, and retains write plus close errors together, matching Node's `handleFdClose` aggregation order.

Apply to an isolated compiler root containing `bend2/` first:

```sh
patch --forward -p1 -d "$BEND_ROOT" < patches/bend-file-mode-close.patch
BEND="$BEND_ROOT/bend2/main.ts" sh scripts/build-pure.sh tests/filesystem-paths.bend build/filesystem-paths
"$BEND_ROOT/bend2/main.ts" tests/filesystem-paths.bend -o build/filesystem-paths.js
python3 tests/filesystem_paths_check.py
python3 tests/filesystem_write_check.py
```

The candidate passes both suites on Bun and native one/four threads: umask 002/027, explicit 0600, existing permission preservation, read/write/append modes, invalid modes, ordinary OS failures, and 128 repeated close EIO/EINTR or combined write ENOSPC/close EIO failures. Test-only hooks close actual descriptors before reporting failure and audit handle retirement under a 64-descriptor limit. The unchanged AES fixture emits byte-identical C under the baseline and candidate; this is a codegen non-regression check, not a claim about filesystem throughput. After isolated validation, the patch was installed on 2026-09-22 in the ordinary, native and cap-hot toolchains. Both suites were rebuilt and passed again through the installed toolchains. Base backups and installation hashes are retained in `build/before-file-mode-close/` and `build/file-mode-close-installation.json`.

`bend-home-directory.patch` adds `Directory.home_bytes()` and the pure Bend `FS.homedir()` decoder. It follows [libuv's POSIX home lookup](https://github.com/libuv/libuv/blob/v1.x/src/unix/core.c): present `HOME` wins, including an empty value; otherwise `getpwuid_r(geteuid())` supplies the directory, retrying EINTR and enlarging the buffer on ERANGE. No normalization, existence check or Unicode replacement happens in the OS effect. The native effect uses POSIX libc. The hosted effect uses the existing small Bun FFI pattern and explicitly supports the Linux LP64 passwd layout on x64/arm64; other hosted platforms return ENOSYS. Node/Bun string APIs replace malformed HOME bytes, and Bun's `userInfo({encoding: "buffer"})` returns a string, so neither is used as a byte source.

```sh
patch --forward -p1 -d "$BEND_ROOT" < patches/bend-home-directory.patch
BEND="$BEND_ROOT/bend2/main.ts" sh scripts/build-pure.sh tests/filesystem-paths.bend build/filesystem-paths
"$BEND_ROOT/bend2/main.ts" tests/filesystem-paths.bend -o build/filesystem-paths.js
python3 tests/filesystem_home_check.py
```

Validated Bun/native one/four threads with empty, relative, nonexistent, Unicode, literal U+FFFD, malformed UTF-8 and absent HOME; passwd EIO/no-entry errors and ERANGE retry; environment precedence over passwd errors. Native also preserves an 8197-byte HOME. Bun 1.4.0 (34cbb9a40) crashes while parsing this generated fixture when launched with that long HOME (`range end index ... out of range for slice of length 4095`), before the effect runs; that hosted case is explicitly omitted, and no workaround or compiler change is included. A trivial Bun script does not reproduce the crash, so this is not claimed to affect every Bun invocation. Existing filesystem path/write checks pass, and the unchanged AES fixture emits byte-identical C. After candidate validation, this patch was installed on 2026-09-22 in the ordinary, native and cap-hot toolchains. The home, path and write suites were rebuilt and passed on Bun and native one/four threads. Base backups and installation hashes are in `build/before-home-directory/` and `build/home-directory-installation.json`.

## Filesystem access and symbolic errno names

`bend-filesystem-access.patch` adds `File.access(path, mode)` and `System.error_name(code)`. These are OS effects only: access checks never open or modify the target, and name lookup is optional when the host has no symbolic errno facility. Native name lookup requires glibc 2.32+; hosted lookup uses the system error-name API. See [scope and checks](../tests/filesystem-access.md). The reviewed patch was installed on 2026-09-22 in the ordinary, native and cap-hot toolchains with unchanged compiler core; backups and hashes are in `build/before-filesystem-access/` and `build/filesystem-access-installation.json`. Replacement toolchains must retain this patch alongside the earlier filesystem primitives.
`bend-worklist-emission.patch` (2026-09-22, applied after the pass memos) replaces the whole-book fact passes by a worklist over the units that read a grown fact; native-agent emission 85 s → 43 s. See the issue log's BEND-001 resolution entry.

`bend-native-f64.patch` (2026-09-22) adds Base's native `F64` (two `U32` words of IEEE 754 bits) with arithmetic, comparison, conversion, shortest decimal spelling and reading as primitives on the host, CUDA and JS lanes (Metal has no `double`; there the operations fail-stop as functions the device does not hold). `bend-translation-units.patch` lets `BEND_TUS=N` deal the generated host segments to N translation units compiled in parallel by `scripts/build-pure.sh`; the native agent builds in under a minute instead of about four. Both are installed in `build/bend-native-toolchain/bend2`; evidence is in the issue log's BEND-013 and BEND-016 entries.

`bend-u32-mul-hi.patch` (2026-09-22, installed) adds `U32.mul_hi`, the high word of the 64-bit product, as a primitive on both lanes; the big-natural module's 32-bit limbs are built on it. When native-tls was merged back into main (2026-09-23), the 32-bit-limb BigNat was not carried over: native-tls had moved Montgomery arithmetic into `modular.bend` with 16-bit limbs, so the merged tree keeps 16-bit limbs and the primitive is currently unused.
`bend-is-terminal.patch` adds `IO.isTerminal(descriptor: U32) -> IO(Bool)`: `isatty(2)` natively and `tty.isatty` on the JS backend, reporting false for closed or non-terminal descriptors. The coding agent's print mode uses it to decide whether stdin is piped prompt text and whether an unattended stdout selects print mode, as pi does with `process.stdin.isTTY`. It is a one-line OS query; no terminal control or raw-mode handling is added.

`bend-halt-silent.patch` makes `IO.die` with an empty message exit with its code without printing an empty line on stderr (both backends). A non-empty message still prints as one line. The CLI relies on it for pi's silent non-zero exits.

The print-CLI worktree toolchain (`build/cli-toolchain`) also carries `bend-directory-metadata.patch` and `bend-file-lock-effects.patch` from native-tls (its `File.kind`/`Directory.read_bytes` declarations were applied by hand after the hunk offset moved); session discovery orders files by `File.modified_time` from the latter.

`bend-js-explicit-stack.patch` resolves BEND-019 in the JS backend's emitter (`js_stackify`, a post-pass over each def's emitted lines). A def whose arms call itself outside tail position — `h <> f(t)`, `nat_chk(f(t) + 1n)`, `h + (sep + f(t))`, a self-call nested in another call's arguments — is emitted as a `while (true)` loop with a heap array of continuation frames: a non-tail self-call pushes the remainder of its arm as a closure and continues with the callee's arguments (each iteration rebinds the parameters as fresh constants so frames capture that iteration's values), a tail self-call continues, every other return breaks out, and the frames are applied innermost first through the existing `run_loop` trampoline. Closures inside an arm and second self-calls of the same arm keep ordinary recursion. The C backend is untouched. `tests/js_explicit_stack.py` runs the two reproducers (List.append doubling to 65,536 elements; `List.length`/`String.split`/`String.join` over 200,000/50,000/20,000 elements) on Bun and checks the native build agrees; the JS build of the coding-agent CLI rewrites 821 defs, grows 3% and starts in the same 0.15 s.

`bend-file-rename-chmod-unlink.patch` (2026-09-23) adds `File.rename`, `File.chmod` (permission bits up to 0o7777, otherwise EINVAL), `File.unlink` and `File.link_kind`. These are thin effects over rename(2), chmod(2), unlink(2) and lstat(2), with Node `fs` equivalents for the JS backend. The tools-manager needs them for its binary installation, as upstream uses `renameSync`, `chmodSync` and `rmSync`. Recursive and forced removal remain Bend policy. The patch adds one Base block and eight effect files, and changes no compiler or runtime-core code. It is installed in `build/bend-process-files/bend2`. A scratch program checked success, EINVAL and ENOENT on Bun and native. `tests/tools_manager_check.py` exercises the installation path. `File.link_kind` (lstat) was added for `FS.remove`, which must not follow links. `tests/shell.bend` emits byte-identical C against an unpatched copy. Three alternating compiles took 0.47/0.49/0.47 s unpatched and 0.45/0.48/0.48 s patched; this is shared-host noise, not a performance claim.

`bend-fork-free-cuts.patch` (2026-09-23) fixes BEND-033. With more than one worker, a task runs in parallel mode. Every non-tail call (a "cut") then allocated its continuation as a heap task and returned through `FID_EXIT`, even when the callee can never fork. One HTTPS request made about 735M such task exits: the handshake's BigNat limb loops. The emitted cut now takes the ordinary stack-frame path when `seq || fid_nofk(callee)`. `fid_nofk` comes from the existing constant `FID_FLAG_T`, which marks segments that neither fork nor reach a fork or closure application. Calls that may fork, and IO ("bang") calls, keep the task path. The patch is one emitted condition; the runtime is unchanged. It is installed in `build/bend-process-files/bend2`.

Measurements on the shared host:
- **HTTPS request pair** (`tests/https-thread-cliff.bend`): 25.9 s → 7.0 s on 4 threads; 6.8 s vs 7.0 s on 1 thread (unchanged).
- **Full CLI C generation:** 90.0 s / 8.34 GiB → 89.2 s / 8.23 GiB; C output 68.48 MB → 68.91 MB (+0.6%, the added conditions).

These are single measurements, not a guarantee.

Validation with the patched compiler, all passing:
- runtime concurrency suites on 1 and 4 threads;
- 112 parallel tool-batch schedules;
- child-execute (50) and child-process;
- agent-session (95, 1 and 4 threads);
- grep (112) and find (84), native 1/4;
- tools-manager, including the live GitHub download on 4 threads.

`bend-process-clock.patch` and `bend-terminal-effects.patch` (2026-09-23) are installed in the shared toolchain `build/bend-process-files`, which builds the full CLI including the interactive terminal. `bend-terminal-effects.patch` was regenerated to apply after `bend-process-clock.patch` on the current default. Both only add Base declarations and effect files: `tests/session-context-edit.bend` compiles to byte-identical C with and without them, with equal peak memory (1.36 vs 1.33 GB) and compile times within the host's noise (13-20 s for both).


`bend-tcp-readable.patch` (2026-09-23, installed in `build/bend-native-toolchain/bend2`) adds `TCP.readable(socket)`: a zero-timeout `poll` for `POLLIN` that reports whether data, a peer close or an error is pending, without reading. HTTP keep-alive uses it to discard an idle socket the server closed, as undici's idle-socket validation does. `tests/tcp-readable.bend` (loopback: idle false, pending true, drained false, peer-closed true) passes on Bun and native one/four threads; generated C for a program that does not use it (`tests/minimatch.bend`) is byte-identical.

`bend-intrinsic-word-arguments.patch` (2026-09-24, installed in `build/bend-native-toolchain/bend2`) fixes word intrinsics given a boxed argument, such as a generic `Bool.pick` result passed to `||`. The argument is unboxed to the parameter's layout before the C template reads it as a word. A word template's result is labelled with its declared word layout, so nested intrinsics are not mistaken for boxes. Before the patch, `tests/repro/bool-pick-or.bend` printed `false` natively; it now prints `true` on one and four threads. The generated C for the full CLI and for `tests/keys.bend` is byte-identical to the unpatched compiler's. Evidence is under the boxed-Boolean entry in `docs/bend-issues.md`.

`bend-set-env.patch` (2026-09-24, installed in `build/bend-native-toolchain/bend2`) adds `IO.set_env(name, value)`: `setenv` natively and a `process.env` assignment on Bun, so later `IO.get_env`/`IO.environment` reads and spawned processes see the variable, as upstream's startup `process.env.PI_CODING_AGENT = "true"` does. Empty names, `=` in the name and NUL bytes fail with EINVAL. `tests/set-env.bend` (set, read back, reject `A=B`, visible in `IO.environment`) passes natively and on Bun; generated C for `tests/minimatch.bend` is byte-identical.

`bend-app-argv.patch` (2026-09-24, installed in `build/bend-native-toolchain/bend2`) makes `BEND_THREADS` the default native worker count and, for programs compiled with `-DBEND_APP_ARGV` (`BEND_CFLAGS`, see `scripts/build-cli.sh`), hands the whole command line to the program: the runtime no longer consumes `--help`, `--threads`, `--gpu` or `--`, so `pi --help` prints pi's help. Other programs keep the runtime flags. Checked with a program printing its arguments (plain: `--threads 2 -- --help x` → `--help x`, `a --help` → runtime usage; app: every argument verbatim). The Bun lane is unchanged.

`bend-default-threads.patch` (2026-09-24, installed in `build/bend-native-toolchain/bend2`) lets a program set its default worker count at C compile time with `-DBEND_DEFAULT_THREADS=N`; `BEND_THREADS` still overrides it, and without the definition the default stays the CPU count. The pi CLI (`scripts/build-cli.sh`) uses one worker, like upstream's single-threaded Node process: its work is sequential, and extra workers only added fork/join overhead. Measured on the parity scenarios (same binary, `BEND_THREADS=1` vs the 16-CPU default): startup 0.66 s vs 0.83 s, 40-chunk streamed answer 0.50 s vs 0.64 s, tool turn 0.24 s vs 0.31 s, typing unchanged; the full parity suite passes with one worker. The patch changes only the emitted `main`, so compile time is unaffected.

`bend-tcp-callback.patch` (2026-09-24, isolated candidate) adds `TCP.listen_host(host, port)` and one nonblocking `TCP.accept_try(listener)` attempt, leaving the existing listener and parked accept unchanged. They let an OAuth callback server bind only loopback and release its listener on cancellation. `tests/tcp-loopback-accept.bend` passes on Bun and native one/four threads; generated C for `tests/anthropic-oauth-start.bend`, which does not use the additions, is byte-identical (324,983 bytes) with and without the patch.

`bend-wide-arity.patch` (2026-09-25, installed in `build/bend-native-toolchain/bend2`) removes the 255 limit on segment and constructor arities. A segment's parameters are the words live across a call, and inline records count one word per cell, so a def that builds many records in sequence exceeds a byte: `marked`'s `rulesWith` holds 30 compiled searches while building the 31st (271 words), and one constructor reaches 325. The arity tables now use `u16` entries when some entry needs them and stay `u8` otherwise. The wide segments are framed, so the register bank does not widen (35 words in `tests/marked-lexer.bend`). Programs within the old limit get byte-identical C except for the added `u16` typedefs (checked on `tests/interactive-autocomplete.bend`). The native `marked` lexer built with the patch prints the same tokens as its Bun build on all 1,358 cases. `BEND_LAY_MAX` still boxes wide records; its reason is now C size and emission time rather than the table. The patch also fixes the one runtime assumption of byte arities, found by reading the runtime afterwards: `term_drop`'s cursor counts a node's fields in 8 bits, so dropping a node with more than 255 fields leaked the rest and could spill into the size-class bits. Such a node now drops its fields directly (recursing only through wide nodes); `tests/compiler-wide-drop.bend` (20,000 dropped 300-field records) peaks at 359 MB without that hunk and 2 MB with it. The patch is +19 lines.

`bend-register-bank.patch`, `bend-string-literal-arms.patch` and `bend-stale-segments.patch` (2026-09-25, applied in that order, installed in `build/bend-native-toolchain/bend2`; the compiler is then 11,319 lines, +5.2% over Bend 2.0.7). The first caps every segment's register signature at `BEND_BANK` (32) words, with wider definitions and closures taking their first words on the stack as continuations do (BEND-039). The second compiles a column of string literals into one arm per literal instead of a character trie (BEND-040). The third drops stale segments once after the facts' fixed point instead of filtering the whole list per unit (BEND-041), with byte-identical output. Measured together on the CLI (BEND-042): emission 457 s → 149 s, C 169 MB → 140 MB, Clang 504 s → 270 s, parity unchanged.

`bend-unit-contents.patch` (2026-09-25, installed in `build/bend-native-toolchain/bend2`, after the three above): with several translation units, unit 0 holds the static image and dispatch table and no segments, and other units declare only the segment functions they name (BEND-043). The CLI's Clang time drops from 270 s over four units to 102 s over sixteen, at about 1.5 GB per unit.

`bend-emission-memos.patch` (2026-09-25, installed after `bend-unit-contents.patch`): a set-based duplicate-id check and memoized word values and constructor macros (BEND-044). CLI emission 151 s → 129 s, byte-identical output.

`bend-unit-spins-image.patch` (2026-09-25, installed after `bend-emission-memos.patch`): the static image as integer literals with a relocation list for the loader, and each translation unit holding only the spins its segments reach (BEND-045). CLI Clang: slowest unit 97 s → 84 s, unit 0 45 s → 12 s, 1.5 → 1.3 GB per unit; parity unchanged. The compiler is then 11,401 lines.

`bend-literal-folds.patch` (2026-09-25, installed after `bend-unit-spins-image.patch`): F64 arithmetic on literals is folded at compile time, so records holding such values (the model catalogs) go into the static image, and literal fields of shared nodes are not sealed (BEND-047). CLI C 148.0 → 142.2 MB, slowest Clang unit 85 → 78 s; parity unchanged. The compiler is then 11,434 lines.

`bend-book-caches.patch` (2026-09-25, installed after `bend-literal-folds.patch`): per-definition cache clearing keeps the two caches that depend only on the book (BEND-049). CLI emission about 140 s → 128 s, byte-identical C, slightly lower peak memory.

`bend-match-binder-order.patch` (2026-09-25, installed after `bend-book-caches.patch`, changes `bend.ts`): a match column that destructures the next parameter is decided before earlier columns, so `match x setup` with a skipped then destructured `setup` compiles (BEND-050). The CLI's C is byte-identical.

`bend-compare-congruence.patch` (2026-09-26, installed after `bend-match-binder-order.patch`, changes `bend.ts`): conversion first tries the same definition applied to convertible arguments before unfolding either side, so comparing stuck terms that mention a Nat constant of 65,536 or more no longer overflows the checker's stack (BEND-052). CLI checking slightly faster, C byte-identical. The compiler is then 11,453 lines.

`bend-segment-memory.patch` (2026-09-26, installed after `bend-compare-congruence.patch`, changes `comp.ts`): stale segments and spins are dropped after every fact round instead of after the last, and a finished unit's segment lines are joined into one string (BEND-053). CLI emission peak 17.6 → 15.6–16.4 GB, time unchanged within noise, C byte-identical. The compiler is then 11,465 lines.


`bend-incremental-ids.patch` (2026-09-26, installed after `bend-segment-memory.patch`, changes `comp.ts`): unchanged code emits byte-identical C across builds (segments numbered within their definition, spins and static tables named by content, `BEND_IDS` keeps segment and constructor ids and the image layout), each definition goes to a fixed translation unit, and units read the shared tables as `extern`. With `scripts/build-incremental.sh`, a one-string edit recompiles 2 of 64 units: 146 s against 210 s for the ordinary build. See docs/incremental-build.md. The compiler is then 11,539 lines.

`bend-id-width.patch` (2026-09-26, installed after `bend-incremental-ids.patch`, changes `comp.ts`): segment and constructor ids widen from 16 to 20 bits (the tag keeps 3 bits), and the incremental id map compacts before it would exceed the range (BEND-055, BEND-058). The CLI needed 65,114 of the former 65,536 ids.


`bend-external-editor-primitives.patch` adds native POSIX `Process.spawn_inherit` and `Directory.mkdtemp`. The former preserves foreground process-group membership and stdio, resets child signal state, and returns an affine process owner for the existing wait/reap operations. The latter atomically creates a 0700 directory from a template ending in `XXXXXX`. Neither primitive supplies editor policy; temporary-file preparation, text normalization and cleanup live in `external-editor.bend`. JS effects return ENOSYS, as existing native process effects do. Apply with `patch -p1 -d build/bend-native-toolchain < patches/bend-external-editor-primitives.patch`.

Validation: build `tests/process-inherited.bend` and `tests/external-editor.bend` with `scripts/build-pure.sh`, then run `python3 tests/external_editor_check.py`. The candidate passed native1/native4 foreground PTY and upstream helper comparisons, plus the existing `process_primitive_check.py` (34 lifecycle scenarios per lane and 128 retirement/reuse pairs). The unchanged process fixture produced byte-identical preprocessed C in both translation units against the unpatched baseline; an alternating 30-sample process-launch comparison measured 2.51/2.63 ms medians, within shared-host noise. The additions change no compiler or runtime-core code.

`bend-borrowed-scalars.patch` (2026-09-26, installed after `bend-id-width.patch`, changes `comp.ts`): a scalar read out of a borrowed parameter is a copy and no longer makes the parameter owned (BEND-054). Reading every scalar of a shared million-element list 100 times: 1.25 s → 0.26 s.

`bend-import-binders.patch` (2026-09-26, installed after `bend-borrowed-scalars.patch`, changes `bend.ts`): a pattern or lambda binder named like a definition of its own module is a binder in an imported module too, as it is in an entry file (BEND-032). The CLI's C is byte-identical.

`bend-js-explicit-stack.patch` (2026-09-26): installed in the shared toolchain, after `bend-import-binders.patch`. It had only been installed in the old CLI worktree's toolchain, so the Bun lane still overflowed on deep non-tail self-recursion (`tests/compiler-js-*.bend`). Regenerated against the current `comp.ts`: `js_def` now records `start`, the line where the function opens, which the rewrite needs and which a predecessor change used to provide. `tests/js_explicit_stack.py` passes, the five other `compiler-js-*` reproducers print their results on Bun, and interactive messages and markdown.test.ts (81/81) match on the Bun lane. The C backend is unchanged. The compiler is then 11,707 lines.

`bend-named-column-binders.patch` (2026-09-26, installed after `bend-js-explicit-stack.patch`, changes `bend.ts`): a flattened match column's binder takes its name from the first row that names the field, so linearity errors name the binder and its case instead of an earlier wildcard (BEND-059). Only generated local names change.

