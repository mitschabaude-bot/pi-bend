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
