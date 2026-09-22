# Project context loading

`core/resource-loader.bend` implements `loadProjectContextFiles` from pinned `pi-mono@46c9de402`. It loads global context first, then ancestors from the filesystem root through cwd. Within each directory it selects the first readable regular file among `AGENTS.override.md`, `AGENTS.md`, `AGENTS.MD`, `CLAUDE.md`, and `CLAUDE.MD`. It strips one leading BOM, preserves the rest of the contents, and deduplicates reported lexical paths. There is no depth cap.

`loadProjectContextFiles(Paths.Environment, Options{cwd,agentDir})` returns `IO(ContextFiles{files,diagnostics})`. Files use the existing `SystemPrompt.ContextFile` type. Recoverable read/decoding errors become warning diagnostics and discovery tries the next candidate, replacing upstream console output with data. Invalid UTF-8 is rejected rather than replaced. Invalid path inputs produce diagnostics. Configuration supplies the explicit path environment; no ambient cwd/home policy or console printing is hidden in the library.

`core/footer-data-provider.bend` implements the reusable `GitPaths{repoDir,commonGitDir,headPath}` and `findGitPaths(absoluteCwd) -> IO(Maybe<GitPaths>)`. It walks ancestors, follows `.git` directories and `gitdir:` files, requires the target HEAD, and resolves an optional commondir relative to that gitdir. These paths let context loading suppress only the same-filename main-repository context shadowed by a nested linked worktree. Canonical paths handle symlinked cwd spellings. Ordinary repositories, sibling worktrees, bare layouts and submodules retain their normal ancestors. Missing or malformed Git metadata gives no Git result, following upstream's optional discovery contract; raw invalid UTF-8 metadata is likewise rejected.

## Checks

```sh
BEND=/path/to/bend2/main.ts
"$BEND" tests/project-context.bend -o build/project-context.js
python3 tests/project_context_check.py -- bun build/project-context.js
BEND="$BEND" BEND_TUS=8 sh scripts/build-pure.sh tests/project-context.bend build/project-context
python3 tests/project_context_check.py -- build/project-context --threads 1
python3 tests/project_context_check.py -- build/project-context --threads 4
```

Final validation passes on Bun and optimized native execution with explicit one/four workers.

The reference extracts and executes the actual pinned `findGitPaths`/context functions and all nine named `loadProjectContextFiles - nested worktree dedup` tests, retaining their assertions. Additional filesystem scenarios directly cover the context assertions from “should prefer AGENTS.override.md within each directory while preserving ancestor layering” and “should ignore context file candidates that are directories”; they do not construct or claim a completed DefaultResourceLoader. The resulting 32 complete context/Git comparisons retain exact file paths, text and ordering. A separate malformed-UTF-8 case verifies diagnostic plus fallback behavior.

Other cases exercise all five candidate names, leading/interior BOMs, empty-file precedence, lexical deduplication when the agent directory is an ancestor, file/broken symlinks, FIFO skips without opening content, relative/absolute Git targets, commondir resolution, missing HEAD, unrelated `.git` files, symlinked worktree shadowing, a 180,000-byte context file and 70 ancestor levels. Temporary directory skeletons need no Git executable and never alter real repositories or the account's HOME.

## Remaining scope

This is explicitly a partial ResourceLoader and FooterDataProvider port. Extension/theme/package discovery, reload orchestration, project trust and `noContextFiles` option wiring, prompt overrides, and footer branch/watch/subscription state remain owned by those future implementations. No placeholder method claims they work. CLI integration can consume the completed context loader directly.
