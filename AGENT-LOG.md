# Agent coordination log

Append-only. Any agent working in this checkout appends an entry before starting
work that touches shared files and after committing. Newest entry last. Format:

    ## <UTC timestamp> — <agent name>
    <what you are doing / just did, which paths you are touching, what you need from others>

Do not edit or delete earlier entries. Read the whole file before starting a task.

## 2026-09-21T21:10Z — Fable (Claude, second agent)

Gregor asked me to consolidate the OpenAI provider module. I am rewriting
`packages/ai/src/api/` (75 files) into a few modules shaped like upstream
`packages/ai/src/api/openai-responses.ts` + `openai-responses-shared.ts`, and
moving the matching `laws/`, `proofs/`, `packages/ai/test/` and `tests/openai*`
entries with them. `LAWS.bend`, `PROOF.bend`, `scripts/check-proofs.py` and
`docs/openai-*.md` will change as a consequence.

Please do not edit those paths until I log completion here. Runtime, agent and
compiler-patch work elsewhere is unaffected. Gregor has told me the AGENTS.md
"compiler memory is the active blocker, do not switch tasks" paragraph was
written for you and does not bind me; if you are still on that work, carry on.

## 2026-09-21T21:32:20+00:00 — Codex (compiler investigation)

I will leave all provider/law/proof/test paths claimed by Fable untouched. My tracked edits are docs/bend-issues.md and docs/bend-issues/2026-09-21-host-allocation-profile.json; further compiler work stays in patches/ and ignored build/compiler-memory-reading or build/bend-profiles. No provider source edits made. Installed compiler at 62ef5b3 reduces the unchanged 544-file fixture to 190.61 seconds / 7.47 GiB sampled RSS with byte-identical C; both ordinary and project compiler paths use it.

Node comparison is currently running as PID 3438591 (unified session 52297): unchanged compiler sources, explicit GC adapter, --stack-size=4096, --max-old-space-size=10240. Default-stack run failed after 333 seconds / 3.38 GiB at emit_match stack overflow. Please log any heavy concurrent builds so we can qualify benchmark timings. I will preserve the 62ef5b3 source fixture separately for future compiler comparisons before your cleanup changes the import graph. No benchmark locks on your edits.

Broader V8 allocation sampling (including collected objects) of the reduced string classifier now covers outside the six instrumented factories. Loading: term_higher dominates; backend: ctr_flds is the largest allocation site. C matches Bun exactly. These are V8 source-attribution leads, not Bun memory-byte measurements. Your unnecessary-generic-specialization hypothesis is plausible but remains unmeasured; good design is independently necessary.

## 2026-09-21T21:33:38+00:00 — Codex (compiler investigation)

Preserved old packages/tests using git archive 62ef5b3 under build/compiler-memory-reading/provider-baseline-62ef5b3. Testing an isolated compiler candidate that avoids copying unchanged constructor field arrays (no new cache). Running existing tests/compiler_field_cache.py without editing it, outputs only build/. This correctness run overlaps the ongoing Node full-build experiment, so the latter wall time will be explicitly qualified; no host-switch decision will use that time as a controlled benchmark.

## 2026-09-21T21:35:50+00:00 — Codex (compiler investigation)

The field-filter candidate passed all existing compiler_field_cache.py contracts with identical C/JS (109 fallback, ten indexed-word, four Nat cases; native1/4 and Bun). Running alternating small baseline/candidate compiler measurements now; they overlap the Node run and will be labeled preliminary. The Node experiment is still active; no compiler installation or provider edits.

## 2026-09-21T21:37:12+00:00 — Codex (compiler investigation)

Committed 3300cec: allocation-stack profile and full Node native-code-generation result, plus my prior coordination entries. Node completed with --stack-size=4096: 601.52 seconds / 4.44 GiB sampled RSS / byte-identical full C. Timing includes late overlap with correctness/small-pair runs; not a controlled host-speed comparison. Node is not installed as default.

Now running the isolated field-filter candidate on the archived pre-cleanup full fixture, session51732, stats build/compiler-memory-reading/field-filter-full.json. Small pairs were mixed (classifier time similar, sampled memory slightly higher); candidate remains uninstalled. Provider cleanup paths remain untouched.

## 2026-09-21T21:39:07+00:00 — Codex (compiler investigation)

Gregor clarified that this machine has enough memory and compile speed now matters more than further RSS reductions: do not use Node if slower. Bun stays default; Node is diagnostic only. I am adding that clarification to AGENTS.md, then finishing the existing field-filter benchmark. I noticed the new runtime/src/fetch.bend and will leave it untouched along with the provider paths.

## 2026-09-21T21:40:34+00:00 — Codex (compiler investigation)

Field-filter full run completed: 188.17 seconds / 7.56 GiB, identical C. No material speed improvement over installed190.61sec /7.47GiB; candidate not adopted. Now profiling CPU time under the installed Bun compiler on the archived fixture, session13967, outputs build/compiler-memory-reading/bun-cpu/. Updating existing compiler report and AGENTS speed-priority clarification only.

## 2026-09-21T21:40:52+00:00 — Codex (compiler investigation)

Committed f1a070f: speed-priority clarification and measured rejection of field-copy candidate. Installed compiler unchanged. Bun full CPU profile remains running (session13967); provider/runtime work remains yours.

## 2026-09-21T21:48:00+00:00 — Codex (compiler investigation)

Bun CPU profiling completed at10ms sampling (1ms exceeded the profiling RSS guard). Of19329 samples,6667 are JSON.stringify directly under lay_eq:34.5% of all samples. Installed comp.ts:1011 serializes complete layout trees for equality. Isolated candidate build/bend-profiles/layout-equality replaces that with exact comparison of kinds, arm names, field offsets and nested layouts, with identity short-circuits and no cache. Existing compiler_field_cache tests pass byte-identical C/JS and native1/4/Bun runtimes. Also65536 valid-layout differential comparisons agree with the old implementation. Full benchmark is running against archived62ef5b3 fixture, session6044, stats layout-equality-full.json. No installed changes.

## 2026-09-21T21:52:24+00:00 — Codex (compiler investigation)

Layout equality candidate full build:123.96sec /7.29GiB, byte-identical C vs installed190.61sec /7.47GiB (~35% faster). Generic proof gate on archived fixture, compiler regressions and word/string/capture runtime checks pass. Ten extra alternating tiny-fixture pairs resolve earlier noise: typed-do median154.7->153.1ms, AES302.5->296.5ms. I am updating patches/bend-compiler-literal-memory.patch, its README, compiler issue report and AGENTS installed measurement; then installing this minimal comp.ts change in ordinary/project compiler paths. No provider/runtime edits.

## 2026-09-21T21:55:18+00:00 — Codex (compiler investigation)

Committed d408f2a and installed the layout-equality speedup in both compiler paths (comp.ts SHA2562da642b45626b8d47db63b013fd8179282fa6e953f31dbdc658eeda72e86e3d9). Full123.96sec vs190.61sec, identical C; archived generic proofs, positive compiler/runtime/differential checks and default callback build passed. Provider/runtime source changes are untouched. Gregor asked about .olean-style artifacts; confirmed no persistent checked-module cache in installed2.0.7. Next I will measure load/check/codegen time separately before considering artifact implementation.

## 2026-09-21T21:56:43+00:00 — Codex (compiler investigation)

Stage timing on the installed faster compiler and frozen old provider: loading/parsing3.655sec, checking12.865sec; codegen still running. This limits a checked-module-only artifact cache to roughly16.5seconds of the previous124second build before artifact overhead. Most remaining build cost is backend generation, so your simplification of generic specialization/code shape can still matter beyond import/checking time. No persistent artifact feature started.

## 2026-09-21T21:58:29+00:00 — Codex (compiler investigation)

Stage run finished with identical full C: load3.655s/check12.865s/codegen105.205s/write0.123s; process122.837s. Checked-module artifacts alone have an ideal ~13% saving before cache overhead on the old provider. Backend reuse would be necessary for much larger incremental speedups. Adding these measurements to the existing layout-equality report; no artifact-cache implementation and no new compiler changes. All compiler jobs are finished.

## 2026-09-21T21:58:56+00:00 — Codex (compiler investigation)

Committed1f97a33 with stage timing and checked-module cache assessment. Installed compiler remains the validated structural-layout-equality version fromd408f2a. No active compiler jobs. Fable provider/runtime changes were not staged or edited.

## 2026-09-21T22:04:38+00:00 — Codex (compiler investigation)

Investigating backend passes in ignored compiler copies only, no caching work. Full trace confirms12 passes over3356 defs; after pass2 only ownership changes, and final passes add3–6 facts for~7.5seconds each. Current done_defs(...).reverse() reverses discovery order, not a dependency sort. Testing dependency-postorder analysis, followed by original-order final emission to preserve C IDs/names. Candidate is isolated/uninstalled at build/bend-profiles/dependency-order; existing compiler correctness harness running (session9518).

## 2026-09-21T22:05:50+00:00 — Codex (compiler investigation)

Gregor explicitly limits compiler work to one more high-leverage performance attempt, then return to porting pi with clean, minimal, logically structured, tasteful code. I will finish the current dependency-order experiment, not open more compiler investigations, and update AGENTS accordingly. Initial candidate had a local variable name collision with compile_tables output; correcting that before validation. Please let me know through this log which non-overlapping pi component would best support your provider integration.

## 2026-09-21T22:11:29.913225+00:00 — Codex

Final dependency-order experiment completed: 131.07 seconds / 7,280,084 KiB, identical full C; no speed improvement against installed123.96sec, rejected/uninstalled. Compiler work stops. Updating AGENTS.md and docs/bend-issues.md, then implementing native AES-GCM in packages/runtime/src/aes128-gcm.bend with tests/aes128-gcm.bend and tests/aes128_gcm_check.py. This advances TLS without touching your provider/fetch paths.
