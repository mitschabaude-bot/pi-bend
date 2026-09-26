# Native combined autocomplete

`packages/tui/src/autocomplete.bend` ports the combined provider from pi-mono `f07218c4d` (v0.87.1), `packages/tui/src/autocomplete.ts`. One module owns slash-command fuzzy matching, asynchronous argument callbacks, token/quote extraction, cursor edits, direct filesystem completion and recursive `@` suggestions. The runtime `file-search.bend` cursor supplies ignore-aware traversal without a production `fd` subprocess or a TUI dependency on coding-agent code.

`create(commands, basePath, homePath, sortPolicy, recursiveFiles)` requires absolute base/home paths. `getSuggestions(provider, lines, cursorLine, cursorCol, Options{signal, force})` returns an IO typed result containing optional suggestions; `applyCompletion` and `shouldTriggerFileCompletion` are pure typed results. `Command` distinguishes actual slash-command declarations from plain autocomplete items. Argument callbacks are caller-owned `Callback` handles: calls await their IO result, propagate typed failure, and do not acquire a provider lock or retain a background task. Dispose callbacks only after outstanding suggestion calls finish. `asProvider` wraps the combined implementation in the editor's typed suggestion, completion and trigger callbacks; `disposeProvider` retires those wrappers after editor requests finish. Applications may also supply their own typed callbacks.

Recursive search checks cancellation before filesystem work, during traversal and before publishing results. A shallow pass and recursive pass each collect at most 100 matching entries, deduplicate their union, rank by match score/depth/path length/selected ordering and return 20. Symlink targets are followed with per-ancestry canonical-path cycle checks; separate aliases remain visible. `.git` is excluded. `.fdignore`, `.ignore`, repository Git exclusions and global configuration use the shared runtime policy, with `.gitignore` outside a repository ignored as in autocomplete's ordinary fd invocation. Cancellation cannot interrupt an already-running filesystem effect; no directory handles or child processes remain owned by the cursor.

## Evidence

`autocomplete_original.mts` hash-checks and loads the actual pinned TypeScript implementation and all 36 original tests (33 in `autocomplete.test.ts`, 3 in `autocomplete-skill-slash.test.ts`) with Node's TypeScript stripping, used solely as a test oracle. The source's separator regexes come from the pinned `utils.ts`. Cursor columns are converted between the source's UTF-16 offsets and native scalar offsets at the adapter boundary. The assertions run through the Bend adapter against live temporary trees, including quoted paths, direct-child flooding, symlinks and exact cursor edits. Every source call also compares the complete ordered result on that same tree, with the native provider using the production `LocaleOrder` (root collation), except the flooding case where the original assertions check the meaningful bounded-search guarantee. Ten additional slash/callback source comparisons, six edit comparisons, and 314 prefix cases (including a 50,000-character line) cover the remaining pure/callback paths.

`autocomplete_check.py` adds 33 explicit native-policy checks: both ordering choices, quoted directories, cancellation, callback failure, scalar cursor coordinates, invalid ranges/prefixes, literal backslashes and regex punctuation, tilde filenames versus home expansion, newline/whitespace filenames, symlink cycles/aliases/broken links, FIFO exclusion, repository/global ignore behavior and invalid UTF-8 rejection. Bun and native one/four-thread execution are checked. The shared traversal extension also preserves all 85 public Find and 109 public Grep cases on all three backends.

## Explicit adaptations and remaining scope

- `LocaleOrder{collator}` orders labels and paths with the runtime root collation, as upstream's `localeCompare`; interactive mode uses it. `ScalarOrder` and `FoldedScalarOrder` remain for callers without collation data (the explicit policy checks also exercise them). Folded prefix matching uses the Unicode case-fold tables rather than JS lowercase/UTF-16 behavior.
- Cursor offsets, path lengths and string operations count native Unicode scalars. Invalid line/column/prefix edits return typed errors instead of JS slicing/coercion behavior.
- Directory-first direct sorting uses the item label, as upstream does since v0.87.1.
- Native paths retain literal Unix backslashes, newlines and surrounding whitespace. Only `~` and `~/` expand to home; `~name` is an ordinary filename, correcting upstream's inconsistent directory/display handling. Windows path behavior remains unported.
- Attachment queries are literal, matching the final scorer's meaning. Pi passes bare queries through fd's regex parser first, causing literal regex punctuation to disappear or misfilter. The Bend implementation fixes that mismatch; none of the 36 named source tests require regex-query behavior. Queries beyond the existing runtime literal-regex compilation bound return a typed error.
- Bounded traversal selection is deterministic scalar directory order. Parallel fd can choose a different subset when more than 100 matches qualify. Direct-child priority and final ranking are preserved; exact scheduler-dependent over-limit subsets are not promised.
- Ordinary inaccessible/missing filesystem paths yield no suggestions as upstream does. Invalid encoded names/configuration, malformed ignore patterns and argument-callback failures remain typed failures rather than silent catch-all suppression.

Prefix/cursor scanning is linear and tail-recursive. Literal matching uses the existing regex runtime's literal matcher. Candidate storage is bounded to the two 100-entry passes, and their merge/ranking is bounded independently of tree size. The filesystem cursor additionally stores pending directory entries, ignore scopes and ancestry; a single directory is currently materialized by `FS.readDirectory`, so total traversal memory is not claimed to be constant. No compiler patch, production JS oracle or negative law test is introduced.

```sh
build/bend-native-toolchain/bend2/main.ts tests/autocomplete.bend -o build/autocomplete.js
BEND_TUS=8 sh scripts/build-pure.sh tests/autocomplete.bend build/autocomplete
python3 tests/autocomplete_check.py
```

Root integration independently rebuilt hosted/native artifacts with the shared compiler and passed the full autocomplete runner on all three backends. The same integrated traversal also passed all 85 Find and 109 Grep scenarios on each backend.

## Interactive provider

`modes/interactive/interactive-mode.bend` ports `createBaseAutocompleteProvider`: the built-in slash commands (`core/slash-commands.bend`), prompt templates and `skill:` commands with their `[u]`/`[p]` source tags, and argument completions for `/model`, `/thinking` and `/login` that read the live session. `@` file search is enabled when managed-tool setup finds fd, as upstream's `fdPath`, although the search itself is native. The provider is rebuilt after `/reload`; extension commands and autocomplete wrappers wait for the extension runtime. `tests/interactive-autocomplete.bend` runs upstream's two `createBaseAutocompleteProvider` cases, and the `autocomplete-*` parity scenarios compare the popups with pi.
