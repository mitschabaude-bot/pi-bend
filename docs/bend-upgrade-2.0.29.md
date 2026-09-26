# Upgrading from Bend 2.0.7 to 2.0.29 (assessment, 2026-09-27)

This is the status of the evaluation that started from `patches/series`, which is upstream 2.0.7 (`fb366635`) plus 72 patches. The work lives in two local, unpushed places:

- `build/bend-work`: a clone of bendlang/bend.
  - Branch `series-2.0.7` is the series as commits.
  - Branch `port-2.0.29` holds the patches ported so far.
- `build/wt-29`: a pi-bend worktree, branch `bend-2.0.29-sources`, with source changes that also check under 2.0.7.

## What carries over

- **Clean cherry-picks (38 patches):** git's 3-way merge applies these onto v2.0.29 unchanged. They include every effect family.
- **Ported by hand:** `bend-monotonic-nanoseconds`, `bend-native-f64` and `bend-u32-mul-hi`.
  - F64 needed the runtime's new names: `u32`, `CID(Name)`, and the two-argument `io_node`/`io_box`.
  - Both lanes print the expected values for `tests/compiler-f64-fold.bend` and a `U32.mul_hi` probe.
- **JS effect registration:** 2.0.28 changed how JS effects register. Every JS effect we add now ends with `io_eff(CID(Def), fn, fn_need)`, generated from the Base defs that import the file.
- **Dropped in favour of upstream:**
  - Upstream now has `File.write_bytes`, with the same signature and semantics as ours (EINVAL above 255, before writing), so ours is gone.
  - `js_sat` already escapes injectively, so `bend-js-identifiers` is obsolete.
  - Literals are single `Lit` nodes, so the literal-sharing half of `bend-compiler-literal-memory` is obsolete.

## Language changes our sources must follow

These rules come from upstream 2.0.16–2.0.28. All the source edits below are also valid under 2.0.7.

| Rule | Our change |
|---|---|
| A bare operator needs a type (`(a + b : Nat)`) | 1,351 sites rewritten mechanically. A scan-only checker records every unannotated operator span. |
| A module can't redeclare a Base name | Constructors `Close` (file-fold), `Key` (collation, uuid) and the names `Event`, `Listener`, `Pair`, `Result`, `Window` renamed. `Listener` in agent-session became upstream's `AgentSessionEventListener`. |
| An import alias can't shadow a Base namespace | 23 aliases renamed (`File`, `Image`, `Word`, `Connect`, `Timer`, …). `Alias.X` moved only where X resolved to the module under 2.0.7's rule. |
| Import paths are plain names | `<provider>.models.bend` became `<provider>-models.bend` (upstream `<provider>.models.ts`), and `image-models.generated.bend` became `image-models-generated.bend`. The generator was updated. |
| A template can't call a def defined below it | Three helpers were moved above their templates. |

## Blockers found so far

1. **Checker memory.** Type-checking `packages/coding-agent/src/main.bend` with 2.0.29 plus the ported patches passed 28 GiB in 132 s and was killed. The same check fits in about 7 GiB on our patched 2.0.7. The cause isn't known yet. The checker-side memory patches that don't port are the likely suspects.
2. **JS lane stack depth.** Six fixtures overflow the JS stack again: `compiler-js-{bool-recursion,list-length,string-join,string-split,test-scalar-format,udp-render}`. So `bend-js-explicit-stack` (BEND-019) is still needed.
3. **Emitter and performance patches not yet ported (29).** These include `bend-incremental-ids`, `bend-id-width`, `bend-translation-units`, `bend-register-bank`, the segment and unit patches, and the literal and string-arm patches. Upstream rewrote the emitter heavily ("16 types instead of 31"). Each one needs re-measuring against the pi CLI, not a textual port.

## Fixture comparison

`tests/compiler-*.bend` was run on the current toolchain and on the port:

- **Identical:** 28.
- **Newly accepted by 2.0.29 (upstream fixed them):** `copied-field-match`, `dup-binder-after-literal`, `string-pattern-dup`, `template-law-parameter`, `u32-multiple-pattern-dup`.
- **Need annotations:** the rest.
- **Cosmetic:** 2.0.29 also prints unused-argument notes (`- main`).

## Remaining cost

Before the CLI can be checked, built and compared at parity, we still need:

- the checker memory investigation;
- the JS explicit stack port;
- about 29 emitter patches;
- the remaining source migration (tests and other entry points).

This is several days of toolchain work. The 2.0.29 JS lane is reported 2.3x faster, but that is unmeasured on pi.
