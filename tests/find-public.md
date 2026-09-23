# Public find over fd

`core/tools/find.bend` runs `fd` as upstream's `find.ts` does (Gregor's decision of 2026-09-23), with the typed `AgentTool`, `FindToolInput`/`FindToolDetails`, injectable `FindOperations.exists/glob`, `FindGlobOptions`, context cwd, result normalization, cancellation and owned callback retirement.

- Injected operations remain caller-owned. They receive `ignore: ["**/node_modules/**", "**/.git/**"]` and the exact limit, and their order and result count are preserved.
- By default, `utils/tools-manager.bend` finds `fd` (bin directory, then `fd`/`fdfind` on PATH). The tool spawns `fd --glob --color=never --hidden [--no-require-git] --max-results N [--full-path] -- PATTERN PATH` in the process's working directory.
  - `--no-require-git` is passed unless the search path or one of its ancestors holds `.git`.
  - A pattern containing `/` gets `--full-path`, plus a leading `**/` unless it starts with `/`, `**/` or is `**`.
- stdout is split into lines as Node's readline does (`\n`, `\r\n` and a lone `\r`), then each line is trimmed, empty lines are dropped and the rest are relativized.
- A failing exit with output still lists the output. Without output it reports fd's trimmed stderr, or "fd exited with code N".
- A failure to start reports "Failed to run fd: spawn PATH ENOENT". A missing fd reports "fd is not available and could not be downloaded". The release download is still pending in tools-manager.
- An abort at any point reports "Operation aborted", since upstream listens from the start.
- The default path does not check that the search path exists; fd's own "not a directory" error surfaces.

fd decides globbing, ignore files and their priorities, Git boundaries, global excludes and Unicode handling. The native traversal and its documented deviations are gone. `runtime/file-search.bend` remains only for the TUI autocomplete, which upstream also backs with fd.

## Reference assertions and executed checks

The reference is pi-mono `46c9de402` and fd **10.3.0**. `find_public_check.py` exercises 84 public scenarios on native one/four workers against an oracle that runs the same fd with upstream's arguments and applies upstream's line handling, relativization and notices. fd's parallel traversal orders output freely, so listings compare as sets; at a result limit, the count, notice and details compare exactly and the chosen results must belong to the full listing. It covers the five relevant `tools.test.ts` assertions: **“should include hidden files that are not gitignored”**, **“should respect .gitignore”**, **“should surface fd glob parse errors”**, **“should treat flag-like patterns as search text”**, and **“find uses ctx.cwd when provided”**.

The four path-glob assertions from `3302-find-path-glob.test.ts` are covered, together with absolute paths and separator-boundary controls. The sibling and deep-subtree scoping assertions from `3303-find-nested-gitignore.test.ts` are covered separately before and after extending the scoped tree. The six POSIX/root/outside-root/injected-tool assertions from `6104-find-root-relativization.test.ts` are covered, including literal backslashes in POSIX filenames and preservation of directory suffixes. Its five Windows `path.win32` cases remain outside this native POSIX implementation.

Additional checks exercise source priority, inherited ignore files, nested repositories both inside/outside Git, linked worktree excludes, unreadable directories, root files, broken/cyclic symlinks, FIFO metadata, global configuration, injected error and cancellation stages, caller-owned callback reuse after disposal, invalid limits, exact/overrun/zero result limits, 1,001-file traversal, UTF-8 byte truncation, whitespace/newline filenames and Unicode scalar matching.  The runner uses `/var/tmp` because this server currently has `/tmp/.git`; treating temporary paths as outside Git without checking that ancestor would invalidate the boundary tests. Flag-like patterns use a fixture-only argv prefix to bypass the older private Bend runtime's `--help` interception; the public tool receives the original pattern unchanged.

```sh
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=4 sh scripts/build-pure.sh tests/find-public.bend build/find-public
python3 tests/find_public_check.py native-1 native-4 --fd /path/to/fd-10.3.0
```
