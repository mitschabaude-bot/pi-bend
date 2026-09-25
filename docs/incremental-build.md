# Incremental native builds (prototype, branch `incremental-build`)

A full CLI build emits about 148 MB of C and compiles it in parallel units.
After an edit, most of that C is unchanged, but the compiler used to rename
and renumber it, so every unit had to be compiled again. This prototype
makes unchanged code produce byte-identical C, and caches compiled units.

## What it changes

`patches/bend-incremental-ids.patch` (on top of the installed patches,
+74 lines of `comp.ts`):

- **Names by content, not by emission order.** A segment is numbered within
  its definition (`f$k0`, `f$c1`), a spin is named by its callee and a hash of
  its argument layouts, and a static table by a hash of its contents.
  Previously each used one counter across the program.
- **Persistent ids.** With `BEND_IDS=file`, segment ids (FIDs), constructor
  ids (CIDs) and the static image's layout persist between builds. A name
  keeps its number, a new one is appended, and a removed one leaves a hole.
  When holes reach a quarter, numbering starts afresh. These numbers are
  immediates in every unit, so without persistence any added segment or
  literal changed every unit.
- **Units by definition.** With more than two units, a definition's segments
  go to unit `1 + hash(def) mod (n − 1)` instead of the least-loaded one.
- **Units read only what they use.** Arity and flag tables, the image and its
  sizes are `extern` outside unit 0. `fid_nofk(FID_x)` in segment code is
  replaced by its value, and `HEAP_OFF` uses the image's size rounded up to
  2^16 words. Static tables, like spins, are only in the units that reach them.

`scripts/build-incremental.sh`: emits with `BEND_IDS` (kept in the cache
directory), preprocesses each unit (`clang -E -P -DBEND_TU=k`), and compiles a
unit only if no cached object has the hash of its preprocessed text, the
flags and the Clang version. The default is 64 units.

## Measured (2026-09-25, CLI at main 4787bc86 plus Codex's settings work)

| Build | Units compiled | Time |
| --- | --- | --- |
| Cold (`build-cli.sh`, 16 units, with `bend-unit-spins-image.patch`) | 16 | 216 s |
| Cold (incremental, 64 units, empty cache) | 64 | 226 s |
| Same source again | 0 | 146 s |
| One string literal changed | 3 (0, 16, 25) | 155 s |

The binary built incrementally matches the non-incremental build on the full
parity run: 96 MATCH, the same DIFF scenarios, and byte-identical Bend
captures. What remains after an edit is emission, about 125 s:
- type checking, about 28 s;
- the fact rounds: round 1 takes 47 s, and round 2 re-emits 60% of units in 35 s;
- preprocessing, about 10 s.

## Why round 2 re-emits most units

Instrumented on the CLI:
- About 12,800 units are dirtied by a fact about their own parameters, which
  a caller or one of their spins discovers after they were emitted.
- Most of the rest are dirtied by hot-constructor facts found by others.

Restarting a unit as soon as it read a fact that then grew was tried and was
slower (round 1 64 s, round 2 31 s), because most of the dirt is cross-unit.

## Next steps

- Cache type-check results per definition, keyed by its source and its
  dependencies' types (about 28 s per build).
- Cache emitted units across builds, keyed by the definition and the facts
  it read. This needs the final facts of the previous build as a seed that is
  checked afterwards.
- Evict old cache entries. The prototype never deletes objects (about 100 MB
  per full build).

## Use

Install the patch into a copy of the toolchain, then:

```sh
BEND=/path/to/patched/bend2/main.ts BEND_CFLAGS="-DBEND_APP_ARGV -DBEND_DEFAULT_THREADS=1" \
  sh scripts/build-incremental.sh packages/coding-agent/src/main.bend build/pi-cli
```
