# Bend compiler patches

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

All three patches are currently applied locally. Bend automatic updates remain enabled, so a future release may remove them or implement the changes upstream. The module regression checks both diamond-import orders and cycle rejection; `sh tests/transcript.sh` additionally exercises the real ai/agent/runtime dependency graph. The build script does not silently modify the compiler.
