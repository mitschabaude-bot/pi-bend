# Native edit execution

`packages/coding-agent/src/core/tools/edit.bend` implements the canonical edit tool's actual execution and public `createEditTool` factory. It uses the shared file mutation queue, injectable access/read/write callbacks, strict UTF-8 decoding, the native matching/application module, and native diff renderers. The queue covers access through result generation, and in-flight operations settle before releasing ownership even after cancellation. Default callback ownership is explicit; injected callbacks remain caller-owned.

The factory exposes the upstream name, label, description, JSON schema descriptions, preferred JSON-schema sampling, argument preparation and execution callback. Results preserve the success text and `EditToolDetails` fields `diff`, `patch`, and `firstChangedLine`. Disk writes restore the original BOM and line endings; result diffs refer to normalized content without the BOM, as upstream does.

The public boundary accepts `{path, edits: [{oldText, newText}, ...]}` and the intentionally supported legacy `{path, oldText, newText}`. A complete top-level legacy pair is appended when a canonical batch also exists. Empty batches, malformed entries, partial legacy pairs, stringified arrays, and non-array `edits` are rejected before filesystem operations. Unknown extra object fields survive argument preparation. The public schema advertises only canonical `path` and `edits`.

## Deliberate adaptations

The user authorized rejecting malformed input rather than recreating permissive legacy recovery. Upstream's named legacy-input assertion accepting a JSON-stringified `edits` array is therefore changed to rejection. The single-edit object recovery is also rejected. Upstream's non-object preparation pass-through becomes a typed invalid-argument result. Intentional legacy top-level pairs and append ordering remain supported. Reconstructed immutable records replace JS object identity assertions.

Malformed UTF-8 file bytes are rejected without writing, rather than replaced with U+FFFD by `Buffer.toString`. Valid UTF-8, including literal replacement characters, follows ordinary editing. Native filesystem access error names use the optional OS lookup primitive; unsupported native libc lookup retains numeric OS errors. Public character offsets retain the pure edit module's previously documented native-character convention.

## Verification

`tests/edit-public.bend` exercises the public factory, its preparation and execution callbacks, default operations, and retirement. `tests/edit_public_check.py` derives expected edit content and exact display/unified patch metadata from pinned pi-mono source and diff 8.0.4. Its corpus covers original-snapshot batches, Unicode/fuzzy matching with untouched lines, uniqueness/overlap/not-found/no-change failures, all-or-nothing writes, BOM/CRLF, legacy input forms, malformed inputs, invalid UTF-8, named ENOENT/EACCES access errors, and a 200 KB file.

`tests/edit-operations.bend` and `tests/edit_operations_check.py` test injected operation ordering and every cancellation checkpoint, including access failure overridden by cancellation and read/write failures retained over cancellation. Concurrent edits preserve both changes. An aborted edit whose writer is held on a channel retains the shared queue until it settles; a queued write verifies this before writing. Both concurrency tests run through identical and symlink-alias paths. Test callbacks are retired after joins; no timed sleeps or scheduling guesses establish ordering.

Build the two Bend fixtures with the compiler containing the filesystem access/name patch. Use `scripts/build-pure.sh` for native and `bend fixture -o build/fixture.js` for Bun. Both Python drivers support `--bun-only` and `--native-only`; the default runs Bun and native one/four threads. The diff package location can be supplied with `--diff-package`.

## Remaining public integration

The current native `AgentTool` execution input does not yet contain `ExtensionContext`. Per-call `ctx.cwd` overrides remain pending that shared API, while factory cwd and path environment already work. Full extension `ToolDefinition` integration, prompt-contribution registration, `renderCall`/`renderResult`, `renderShell`, and terminal styling remain pending their shared framework. These are not claimed by the execution tests. The overall upstream tools, legacy-input, and file-mutation-queue suites therefore remain partial until the broader port integrates those boundaries.

At the initial handoff, both suites pass Bun and native one/four threads on the exact final source with Clang `-O0`. Optimized validation is separately pending: the operations `-O1` build uses exact final source; the earlier public `-O1` build predates only the final schema description wording. Neither pending build is counted as a completed optimized check.
