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

Both patches are currently applied locally. Bend automatic updates remain enabled, so a future release may remove them or implement the changes upstream. The module regression checks both diamond-import orders and cycle rejection; `sh tests/transcript.sh` additionally exercises the real ai/agent/runtime dependency graph. The build script does not silently modify the compiler.
