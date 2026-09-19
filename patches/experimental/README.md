# Experimental compiler changes

These patches are investigation candidates, not part of the eight patches applied to the installed compiler. They do not run automatically during builds.

`bend-compiler-memory.patch` targets the patched Bend 2.0.7 compiler under Bun 1.4.0. It clears the telescope-decomposition cache at existing temporary-cache boundaries and forces Bun garbage collection after each native code-generation pass. It is deliberately an experiment: the explicit `Bun.gc` call assumes the Bun CLI host and is not a portable solution for other compiler embedding hosts. A weak/bounded cache and reducing pattern-lowering allocations remain open alternatives. See [BEND-001](../../docs/bend-issues.md) for measurements and outstanding questions.

For an isolated test compiler, from the repository root:

```sh
mkdir -p build
cp -a "$HOME/.bend/current/bend2" build/bend-memory-candidate
patch --forward -p2 -d build/bend-memory-candidate < patches/experimental/bend-compiler-memory.patch
```

Use a fresh destination; do not merge a new compiler release into an old candidate directory. Create a local launcher that executes `bun --smol /absolute/path/to/build/bend-memory-candidate/main.ts "$@"`, then set `BEND` to that launcher's absolute path when invoking existing test scripts. The ordinary launcher and its telemetry/update settings remain untouched. To obtain phase measurements with a sampled memory cutoff instead, use `scripts/profile-bend.py --smol --clear-teles --gc-passes` with a source file and a fresh label.

The isolated candidate passed `module_imports.py`, `runtime_identity.py`, `clock_vectors.py`, `date_vectors.py`, `js_identifiers.py`, `static_layout.py` and `static_sum_layout.py`, including their native thread/backend checks. The reduced string-pattern program emitted byte-identical C to the original compiler. All 32 Responses driver comparisons and the canonical library type check also passed. Ten of eleven original terminal-event instances passed on one/four threads; the missing instance depends on the unimplemented provider wrapper. Full driver/native checks used `--batch-size 32` and terminal checks used `--batch-size 8`; passing these regressions does not establish general compiler correctness or resolve BEND-001.

The [socket-control candidate](socket-control/README.md) adds two syscall primitives and a pure Bend interrupt owner, with blocked read/write cancellation tests. It remains isolated and uninstalled pending integration and adoption validation.
