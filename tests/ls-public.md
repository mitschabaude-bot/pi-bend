# Native public ls tool

`ls-public.bend` exercises `AgentTool.execute`, native filesystem operations, injected operations, callback ownership and the explicit context adapter. The production module is `packages/coding-agent/src/core/tools/ls.bend`. The reference is the pinned sibling `pi-mono` checkout, `packages/coding-agent/src/core/tools/ls.ts`.

## Executed contracts

The fixture preserves the upstream `tools.test.ts` assertions **“should list dotfiles and directories”** and **“ls uses ctx.cwd when provided”**. It additionally covers existence/stat/readdir failure precedence, empty directories and empty paths, directory suffixes, following directory and file symlinks, skipped broken/cyclic symlinks, listing a FIFO without opening it, permissions, natural limit validation, default 500-entry and explicit entry caps, counting only successful stats, and not statting the first omitted entry. Byte-cap cases cover exact 50KB, an oversized first line, UTF-8 byte counts, and simultaneous entry/byte notices and details. Six real-directory cases compare output directly with the pinned upstream implementation extracted by the Python runner.

Injected callbacks abort at each filesystem stage. Cancellation joins the active callback and prevents subsequent callbacks; no filesystem work escapes the tool owner's lifetime. The preaborted invocation performs no filesystem operations, even with invalid arguments. Disposing a tool retires its execution callback and its own default operations; injected operations remain usable until their caller retires them. This deliberately uses the established safe native cancellation contract instead of upstream's detached promise rejection while an async filesystem task continues.

`ls_public_check.py` is an integration/oracle runner, not production functionality or a claim of universal proof. Native runs use actual `--threads 1` and `--threads 4` arguments. All 45 scenarios run on each backend, including the full-size 50KB/UTF-8 cases.

## Pending public boundaries and explicit representations


Built-in `ls` rendering is dispatched by the interactive tool-execution component through `renderers/ls.bend`; extension `ToolDefinition` renderer hooks are a separate integration boundary. `LsToolInput`, `LsToolDetails`, `LsOperations`, `LsToolOptions`, typed errors, native execution and `LsContext.cwd` are implemented. Operations are effect callbacks with explicit owners; `stat` returns a value `LsStat{isDirectory}` instead of a JavaScript method.

Negative, fractional, nonfinite and out-of-range limits are rejected, following the user's strict-invalid-input direction. Empty and zero limits retain upstream output behavior. Truncation uses the shared native `TruncationResult`. Its no-effective-line-limit metadata uses `4294967295` instead of JavaScript's `Number.MAX_SAFE_INTEGER`; the 51,200-byte cap necessarily wins first, so output is unaffected. Native OS errors retain typed codes and the shared `Error N: message` format, while tool-specific `Path not found`, `Not a directory`, `Cannot read directory`, and abort messages retain their upstream wording.

## Reproduction

```sh
BEND_TUS=8 sh scripts/build-pure.sh tests/ls-public.bend build/ls-public
python3 tests/ls_collation_check.py native-1 native-4
python3 tests/ls_public_check.py native-1 native-4
```

## Default order

`Ls.createLsTool(collator, …)` is the registered tool (`--tools ls`): local directory listings arrive in Node's `readdir` order (byte order), then sort stably by the collation key of the JavaScript-lowercased name (`runtime/collation.bend`, ICU 78 root, loaded from `packages/runtime/data`), exactly as upstream's `a.toLowerCase().localeCompare(b.toLowerCase())` under Node 24. `tests/ls_collation_check.py` compares 40 entries (case pairs, accents, digits, symbols, Greek final sigma, ß/SS, a ligature, CJK, directories) against `node` running that sort; `createLsToolWithComparator` keeps the explicit-comparator form used by the 45 public scenarios. Without the collation data file the registry falls back to code point order.
