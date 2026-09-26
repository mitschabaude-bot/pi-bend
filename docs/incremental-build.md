# Incremental native builds

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

## Measured (2026-09-26, CLI at main 894f7048, installed after `bend-segment-memory.patch`)

| Build | Units compiled | Time |
| --- | --- | --- |
| Cold, `BEND_INCREMENTAL=0` (16 units) | 16 | 209–212 s |
| Cold, incremental (64 units, empty cache) | 64 | 224 s |
| Same source again | 0 | 135 s |
| One string literal of the help text changed | 2 | 146 s |

What remains after an edit is emission (about 125 s: checking 26 s, the
fact rounds, assembly) and preprocessing. The incrementally built binary
matches the ordinary build on the full terminal parity run.

## Why round 2 re-emits most units

Instrumented on the CLI:
- About 12,800 units are dirtied by a fact about their own parameters, which
  a caller or one of their spins discovers after they were emitted.
- Most of the rest are dirtied by hot-constructor facts found by others.

Restarting a unit as soon as it read a fact that then grew was tried and was
slower (round 1 64 s, round 2 31 s), because most of the dirt is cross-unit.

## Tried: an on-disk cache of checked definitions (rejected, 2026-09-26)

Each definition's checked tree (`def.e`) was stored under a hash of the
definition, and reused while every book entry its check looked up (recorded
through a proxy on the book) had the same fingerprint. Spans were dropped.
Measured on the CLI at main f9824927, 64 units, against 25.5 s of checking
and 129 s / 17.7 GB for the whole emission without the cache:

| Run | Checking | Emission total | Peak memory | C |
| --- | --- | --- | --- | --- |
| Cold (fills the cache) | 118 s | 231 s | 17.9 GB | identical |
| Warm (every definition hits) | 51 s | 278 s | 46.8 GB | differs |

- `def.e` is not first-order: every checked subterm carries its type as a
  cell, `Var("_", -1, ty)`, holding a closure term that several cells
  share. Quoting it (`term_lower(term_higher(e))`) expands that sharing into
  trees: 1.6 GB of cache, 2.6x the emission memory, and different C.
- Fingerprinting every entry by lowering and hashing it took 39.5 s, more
  than checking. Fifteen large data tables take 68% of that (lowering a long
  list literal is superlinear; `unicode-17-regex.ranges` alone takes 20.7 s).

Caching emission instead would skip both the check and the emission of an
unchanged definition, but emitting a unit writes shared state beyond its
segments (spins, the static image, constructor ids, closures, bangs, borrow
maps, three fact sets), all of which a hit would have to replay. In one
process, `compile_unit` already drops and re-emits a unit's contributions,
which is what the fact rounds rely on; that is the machinery a resident
compiler would reuse.

## Use

`scripts/build-cli.sh` builds incrementally by default (`BEND_INCREMENTAL=0`
for the ordinary 16-unit build). Any program:

```sh
BEND_CFLAGS="-DBEND_APP_ARGV" sh scripts/build-incremental.sh <entry.bend> <output>
```

The object cache lives in `$XDG_CACHE_HOME/pi-bend` (or `~/.cache/pi-bend`,
`BEND_CACHE` overrides it) and is shared by all worktrees; objects unused for
three days are removed after each build.
