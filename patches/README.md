# Bend toolchain patches

The project compiles with one patched Bend: `build/bend-native-toolchain/bend2`, which `scripts/build-pure.sh`, `scripts/build-incremental.sh` and the proof scripts use by default. It is fully determined by three things in this directory:

- **Base:** upstream Bend 2.0.7, i.e. [bendlang/bend](https://github.com/bendlang/bend) commit `fb36663571742100b349b84d615a2fdbd37ed678` ("Bend 2.0.7"). This covers `bend2/bend.ts`, `comp.ts`, `base.bend`, `main.ts` and `effs/`.
- **`series`:** the patches in application order. Each one is applied with `patch -p1` inside `bend2/` and is a diff against the state left by its predecessors.
- **`toolchain.sha256`:** hashes of every file in the result.

```sh
scripts/install-bend-toolchain.sh              # rebuild build/bend-native-toolchain/bend2 from upstream + series
scripts/install-bend-toolchain.sh build/X/bend2  # an isolated copy for experiments
scripts/install-bend-toolchain.sh --check      # verify the installed toolchain against the hashes
```

The script clones upstream into `build/bend-upstream` when `BEND_UPSTREAM` names no clone. It installs only a result that matches every hash. Don't replace the toolchain while a build is running (`pgrep -f bend2/main.ts`).

The global `~/.bend` install is not part of this setup. It was patched in place before 2026-09-27, and its `*.orig` files are **not** pristine: they already contain the channel-identity, JS-identifier and clock changes. Use upstream at the commit above as the base.

## Changing the series

1. Make the change in a copy produced by the install script. Then diff that copy against the state after the last patch.
2. Append the diff as a new `bend-<topic>.patch` at the end of `series`.
   - To change an existing patch, regenerate it and every later patch it shifts, so that each patch still applies exactly after its predecessors.
3. Measure correctness and relevant performance against an otherwise identical unpatched copy, as AGENTS.md requires. Record the evidence in [docs/bend-issues.md](../docs/bend-issues.md).
4. Install the result, then update `toolchain.sha256` from the verified copy:

   ```sh
   (cd DIR && find . -type f ! -name '*.orig' | sed 's#^\./##' | LC_ALL=C sort | xargs sha256sum) > patches/toolchain.sha256
   ```

5. Commit the patch, `series` and the hashes together.

## Budget

Gregor capped the compiler proper (`bend.ts` + `comp.ts` + `main.ts`) at +20% over upstream 2.0.7, i.e. 12,722 lines. The measurements:

| | bend.ts | comp.ts | main.ts | total |
|---|---:|---:|---:|---:|
| upstream 2.0.7 | 3,776 | 6,302 | 524 | 10,602 |
| after `series` (2026-09-27) | 3,966 | 7,228 | 524 | 11,718 (+10.5%) |

`base.bend` grows from 2,831 to 3,390 lines. Those lines are effect declarations, and the budget doesn't count them.

## The series

Series order is the order in which the patches are applied. The patches for the checker and emitter come first, and the effect primitives come after them. A new effect only adds Base declarations and `effs/*.c`/`*.js` files.

Evidence, measurements and history live in [docs/bend-issues.md](../docs/bend-issues.md) (BEND-nnn entries). Per-patch validation notes from before 2026-09-27 are in [docs/bend-patch-history.md](../docs/bend-patch-history.md); its installation instructions are obsolete. The design notes for the effect families that began as isolated candidates are in [docs/bend-effects/](../docs/bend-effects/).

### Checker, loader and emitter

| Patch | Change |
|---|---|
| `bend-tcp-callback` | `TCP.listen_host`, `TCP.accept_try` (effects; early in the series for historical reasons) |
| `bend-compiler-literal-memory` | Shares literal trees and fieldless constructors, bounds indentation, and caches fields and layouts. Compiler memory (BEND-001). |
| `bend-hot-constructor-fields` | A generic constructor made reference-counted keeps its record payload's reader consistent (native memory corruption) |
| `bend-shared-import-namespace` | A file imported along two paths gets one namespace |
| `bend-channel-identity` | `Chan.same`, the basis of `Ref.same`/`Callback.same` |
| `bend-monotonic-nanoseconds`, `bend-unix-milliseconds` | `IO.monotonicNanoseconds`, `IO.unixMilliseconds` |
| `bend-process-clock` | `Clock.localTime`, `Process.id` |
| `bend-js-identifiers` | JS symbols escape every non-identifier character injectively |
| `bend-static-layout`, `bend-static-sum-conversion` | Constant-image emission for nested generic constructors; layout conversion of a statically known variant |
| `bend-typed-do-shadow` | A typed `do` binding may shadow a module-level function |
| `bend-word-literal-arms` | A column of word literals compiles to direct arms |
| `bend-layout-cap`, `bend-static-boxed-nodes`, `bend-pass-memos` | Boxes records wider than `BEND_LAY_MAX` and keeps boxed static records in the image; per-pass memos (BEND-010) |
| `bend-worklist-emission` | Fact passes run over a worklist of affected units |
| `bend-native-f64` | Base `F64` on the host, CUDA and JS lanes |
| `bend-translation-units` | `BEND_TUS=N` splits host segments across N C translation units |
| `bend-u32-mul-hi` | `U32.mul_hi` (C `(u64)a*b >> 32`, JS BigInt) |
| `bend-is-terminal` | `IO.isTerminal` |
| `bend-halt-silent` | `IO.halt` exits without runtime output |
| `bend-js-explicit-stack` | Non-tail self-recursion on JS runs on a heap stack (BEND-019) |
| `bend-fork-free-cuts` | BEND-033 |
| `bend-intrinsic-word-arguments` | Word intrinsics accept boxed arguments |
| `bend-set-env` | `IO.set_env` |
| `bend-app-argv`, `bend-default-threads` | `-DBEND_APP_ARGV` gives the program its whole argv; `-DBEND_DEFAULT_THREADS=N` |
| `bend-wide-arity` | Segment and constructor arities past 255 |
| `bend-register-bank` | Register signatures capped at `BEND_BANK` words (BEND-039) |
| `bend-string-literal-arms` | A column of string literals compiles to one arm per literal (BEND-040) |
| `bend-stale-segments` | Stale segments are dropped once after the fixed point (BEND-041) |
| `bend-unit-contents`, `bend-emission-memos`, `bend-unit-spins-image` | Unit 0 holds the static image and dispatch; per-unit memos and spins |
| `bend-literal-folds`, `bend-book-caches` | Literal folding; book-level caches |
| `bend-match-binder-order` | Match binder order |
| `bend-compare-congruence` | `term_compare` tries argument congruence before WHNF (BEND-052) |
| `bend-segment-memory` | Finished segments are held as one string each (BEND-053) |
| `bend-incremental-ids` | Stable ids for incremental builds (`scripts/build-incremental.sh`, [docs/incremental-build.md](../docs/incremental-build.md)) |
| `bend-id-width` | 20-bit segment and constructor ids (BEND-058, BEND-055) |
| `bend-borrowed-scalars` | Borrow lookup only for boxed fields (BEND-054) |
| `bend-import-binders`, `bend-named-column-binders`, `bend-import-copy-binders` | Binders named like an imported def, including `+` binders; named column binders (BEND-032, BEND-059) |

### Effect primitives

| Patch | Base additions |
|---|---|
| `bend-timer` | `Timer.new/wait/cancel/close` |
| `bend-socket-control` | `Socket.duplicate`, `TCP.shutdown`, `Socket.isConnectionReset` |
| `bend-tcp-bytes` | `TCP.send_bytes`, `TCP.recv_bytes` |
| `bend-connect` | `Connect.ipv4/ipv6/wait/cancel/close` |
| `bend-socket-endpoint` | `Socket.endpoint` |
| `bend-entropy` | `Entropy.bytes` |
| `bend-socket-refused` | `Socket.isConnectionRefused` |
| `bend-hostname`, `bend-interface-index` | `IO.get_hostname`, `IO.interface_index` |
| `bend-udp-bytes` | `UDP.bind_family/send_bytes/recv_bytes/connect_peer`, `UDPRead`, `UDPWrite` |
| `bend-filesystem-access` | `File.access`, `System.error_name` |
| `bend-file-mode-close` | `File.open_mode`, `File.close_checked` |
| `bend-filesystem-bytes` | `File.size_bytes`, `File.write_bytes` |
| `bend-home-directory` | `Directory.home_bytes` |
| `bend-file-is-file`, `bend-directory-metadata` | `File.is_file`, `File.kind`, `Directory.read_bytes` |
| `bend-file-lock-effects` | `Directory.create/remove`, `File.modified_time`, `File.set_times_milliseconds` |
| `bend-filesystem-paths` | `Directory.ensure`, `File.realpath_bytes`, `Directory.current_bytes` |
| `bend-process`, `bend-process-null-stdin`, `bend-process-tu` | `Process.spawn/wait/signal/close_checked`, `Pipe`, `IO.environment`, `Process.spawn_null_stdin` |
| `bend-terminal-effects` | `Terminal.acquire/restore/dimensions` |
| `bend-file-rename-chmod-unlink` | `File.rename/chmod/unlink/link_kind` |
| `bend-tcp-readable` | `TCP.readable` |
| `bend-system-identity` | `IO.system_identity` |
| `bend-external-editor-primitives` | `Process.spawn_inherit`, `Directory.mkdtemp` |

## Not installed

`experimental/` holds candidates that are not in `series`: compiler-memory experiments that were rejected or superseded, and the IPv6 connect effect. See [experimental/README.md](experimental/README.md).

`bend-conversion-identity.patch` (2026-09-27, installed after `bend-import-copy-binders.patch`, changes `bend.ts`): replaces the congruence step of `bend-compare-congruence.patch` with a port of [bendlang/bend PR #1075](https://github.com/bendlang/bend/pull/1075) (upstream issue #1071, the BEND-052 limitation). Before normalizing a comparison with a call on either side, conversion checks syntactic identity without unfolding, within 4,096 visits, and otherwise proceeds as before. The congruence step had no budget and walked shared arguments as a tree (BEND-061: `tests/compiler-conversion-shared.bend` did not finish in 300 s; now 0.16 s). The BEND-052 regression, the proof gate and checking the whole CLI pass, the CLI in the same time within shared-host noise (evidence in BEND-061). The PR's upstream `Lit` case has no 2.0.7 counterpart and is dropped. The compiler is then 11,759 lines.
