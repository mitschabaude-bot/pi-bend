# Native line diff

`packages/coding-agent/src/core/tools/diff.bend` implements the line-diff dependency used by Pi’s edit tool and both renderers from pinned `packages/coding-agent/src/core/tools/edit-diff.ts` (`46c9de402`). It is independent of edit matching and normalization. `diffLines` returns immutable `Change` runs; `generateDiffString` returns the display and optional first changed line; `generateUnifiedPatch` returns the file headers and unified hunks. Pass `4n` for Pi’s default context. A `Nat` context excludes negative/fractional values.

The algorithm is Myers shortest-edit search with the same ascending diagonal traversal and deletion-on-tie rule as `diff@8.0.4`. Each path holds remaining input tails and a persistent reversed history. A frontier is swept as neighboring list entries; no indexed matrix or repeated line lookup is needed. Absent edge paths are trimmed, keeping pure insertion/deletion frontiers narrow. Worst-case time is O((N+M)D), measured in line comparisons, with shared path histories rather than copied whole edits. Long line comparisons additionally cost their character length. Tokenization preserves LF/CRLF and an unterminated final line.

The renderers preserve Pi’s old-line context numbering, first changed line in the new file, width based on splitting the complete file including its final empty segment, ellipses, context overlap at twice the context size, zero-length hunk coordinates, file-headers-only output, and missing-final-newline markers. Matching and normalization are separate responsibilities.

Run the focused differential check with the exact test-only dependency:

```sh
mkdir -p build
npm pack diff@8.0.4 --pack-destination build
tar -xzf build/diff-8.0.4.tgz -C build
python3 tests/line_diff.py
```

The driver extracts the two unmodified rendering functions directly from the pinned Pi checkout and imports the downloaded dependency as an oracle. Neither is a production dependency. `--reference`, `--diff-package`, `--bend`, `--backends`, and `--no-build` support isolated runs.

Validation: 1,343 cases pass on Bun, native one thread and native four threads. They cover exhaustive short repeated sequences, deterministic mixed line endings/Unicode cases, hunk boundary gaps, context zero, numbering widths, and 1,000-line insertion/deletion/identity. In addition to exact reference output, the driver checks reconstruction of both inputs, maximal runs, and shortest edit count against an independent dynamic-programming reference for short inputs. These are executed differential/invariant checks, not universal proofs. No upstream suite is marked ported by this dependency milestone; filesystem edit execution and UI integration require their own tests.

## Long-line regression

`tests/line-diff-long.bend` constructs 200,000-character common prefixes inside Bend and checks exact identity, replacement, EOF-newline and surrounding-context results for both renderers. This bypasses command-line and JSON serialization limits. Before the fix, a single identical long line caused Bun’s `bend: memory fault (machine stack overflow?)`: Base `String.eq` routes through `String.cmp`, which reconstructs the compared strings across recursive returns. The shared `runtime/string.bend` scalar `equal` consumes the prefixes tail-recursively without reconstruction; diff comparisons use that helper. No compiler change is required. Base string append/join passed the full long-renderer fixture, so they were left unchanged.

The differential driver runs the positive long-line fixture three times on each backend. On the development server, measured whole-process median wall time and maximum RSS were Bun 5.150s / 288,752 KiB, native one thread 0.470s / 83,328 KiB, and native four threads 0.550s / 89,600 KiB. These include input and expected-output construction plus all nine assertions; they are not isolated per-diff timings. All 1,343 shorter differential cases were rerun on each backend after the change.
