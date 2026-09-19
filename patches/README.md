# Bend compiler patches

Keep patches minimal and check relevant performance against an otherwise identical baseline before installing them. Correctness tests alone are insufficient. Memory experiments must measure time as well as memory; see the limitations and pending performance work in [the Bend issue log](../docs/bend-issues.md).

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

Eight patches are currently applied locally to Bend 2.0.7, including the static-sum conversion and typed-do binding fixes below. The import, channel identity, monotonic/Unix clock, JS identifier, static-layout and typed-do regression scripts pass on this release. Bend automatic updates remain enabled, so a future release may remove them or implement the changes upstream. The module regression checks both diamond-import orders and cycle rejection; `sh tests/transcript.sh` additionally exercises the real ai/agent/runtime dependency graph. The build script does not silently modify the compiler. The separate compiler-memory experiment is not installed.

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
