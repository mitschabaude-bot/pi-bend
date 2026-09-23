# Public grep over ripgrep

`core/tools/grep.bend` runs `rg` as upstream's `grep.ts` does, with the canonical typed `AgentTool`, `GrepToolInput`, `GrepToolDetails`, injected `GrepOperations.isDirectory/readFile`, context cwd, cancellation, output formatting and truncation. Gregor decided on 2026-09-23 that grep shells out to ripgrep like upstream rather than porting it. The native search engine is gone, and so are its binary policy, strict decoding and `RIPGREP_CONFIG_PATH` rejection. rg decides matching, ignore files, binary files and encodings.

- `utils/tools-manager.bend` finds `rg` in the agent's bin directory, then on `PATH`, and otherwise downloads the latest release, as upstream does (`tests/tools-manager.md`). When that fails, the tool reports upstream's "ripgrep (rg) is not available and could not be downloaded".
- The tool spawns `rg --json --line-number --color=never --hidden [--ignore-case] [--fixed-strings] [--glob G] -- PATTERN PATH` through `runtime/child-process.spawn`, in the process's working directory and environment. It parses stdout line by line as JSON match events and keeps stderr separately.
- Reaching the match limit stops rg through a second abort signal. This mirrors upstream's `child.kill()`, and the exit status is then ignored.
- Otherwise, an exit status other than 0 or 1 reports rg's trimmed stderr, or "ripgrep exited with code N". A failure to start reports "Failed to run ripgrep: spawn PATH ENOENT", using libuv's error names.
- Match lines come from rg's `lines.text`, with CRs and the final newline removed. With context, or when rg reports a line as bytes (invalid UTF-8), the file is read once through `readFile`. It is decoded as Node's `readFile(path, 'utf-8')` would be (replacement, BOM kept), and a failed read shows `(unable to read file)`.
- Upstream subscribes to the abort signal only after rg has started, and formats the output after rg exits without checking again. The port does the same: an abort before the spawn (for example during `isDirectory`) or during the context reads lets the search finish, and only an abort while rg runs reports "Operation aborted". The one remaining window is an abort after rg exits and before the final check, which the port reports as aborted while upstream resolves.

## Executed reference assertions

The pinned Pi source is `pi-mono` commit `46c9de402`. The fixture preserves these `tools.test.ts` assertions:

- **"should include filename when searching a single file"**
- **"should respect global limit and include context lines"**, including exclusion of the second match
- **"should treat flag-like patterns as search text"**: the executable payload is not invoked
- **"grep uses ctx.cwd when provided"**

`tests/grep_public_check.py` runs 112 public scenarios on native one/four workers. The tool finds `rg` through a symlink in the temporary home's bin directory. The oracle runs the same `rg` with the same arguments and applies upstream's formatting in Python. `RIPGREP_CONFIG_PATH` supplies `--sort=path`, so that rg's parallel output order is reproducible for both.

Coverage includes:
- regex, literal, case and glob options; contexts; limits
- ignore files and global Git excludes; symlinks and FIFOs
- rg's regex, glob and permission errors, reported from its stderr
- UTF-8 and UTF-16 BOM files, with context reread as UTF-8
- invalid UTF-8 lines reported as bytes; binary files
- long and astral lines; the byte cap
- injected context callbacks and caching; the upstream abort timing
- 64 repeated runs with unchanged `/proc/self/fd` counts
- an abort that kills an `rg` blocked on a FIFO

Process spawning is native-only (the Bun lane has no process primitive), so there is no Bun run.

```sh
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=4 sh scripts/build-pure.sh tests/grep-public.bend build/grep-public
python3 tests/grep_public_check.py native-1 native-4
```
