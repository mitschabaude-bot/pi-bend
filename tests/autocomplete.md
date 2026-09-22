# Native combined autocomplete

`packages/tui/src/autocomplete.bend` ports the combined provider from pi-mono `46c9de402`, `packages/tui/src/autocomplete.ts`. One module owns slash-command fuzzy matching, asynchronous argument callbacks, token/quote extraction, cursor edits, direct filesystem completion and recursive `@` suggestions. The runtime `file-search.bend` cursor supplies ignore-aware traversal without a production `fd` subprocess or a TUI dependency on coding-agent code.

`create(commands, basePath, homePath, sortPolicy, recursiveFiles)` requires absolute base/home paths. `getSuggestions(provider, lines, cursorLine, cursorCol, Options{signal, force})` returns an IO typed result containing optional suggestions; `applyCompletion` and `shouldTriggerFileCompletion` are pure typed results. `Command` distinguishes actual slash-command declarations from plain autocomplete items. Argument callbacks are caller-owned `Callback` handles: calls await their IO result, propagate typed failure, and do not acquire a provider lock or retain a background task. Dispose callbacks only after outstanding suggestion calls finish. The concrete provider API is ready for an editor; an arbitrary pluggable editor-provider ownership interface is not claimed here.

Recursive search checks cancellation before filesystem work, during traversal and before publishing results. A shallow pass and recursive pass each collect at most 100 matching entries, deduplicate their union, rank by match score/depth/path length/selected ordering and return 20. Symlink targets are followed with per-ancestry canonical-path cycle checks; separate aliases remain visible. `.git` is excluded. `.fdignore`, `.ignore`, repository Git exclusions and global configuration use the shared runtime policy, with `.gitignore` outside a repository ignored as in autocomplete's ordinary fd invocation. Cancellation cannot interrupt an already-running filesystem effect; no directory handles or child processes remain owned by the cursor.

## Evidence

`autocomplete_original.mts` loads the actual pinned TypeScript implementation and all 27 original tests with Node's TypeScript stripping, used solely as a test oracle. The assertions run through the Bend adapter against live temporary trees, including quoted paths, direct-child flooding, symlinks and exact cursor edits. Every source call also compares complete item content/membership on that same tree, except the flooding case where the original assertions check the meaningful bounded-search guarantee. Because locale ordering is explicitly unresolved, those item comparisons ignore order; the original ranking assertions still execute unchanged. Ten additional slash/callback source comparisons, six edit comparisons, and 314 prefix cases (including a 50,000-character line) cover the remaining pure/callback paths.

`autocomplete_check.py` adds 33 explicit native-policy checks: both ordering choices, quoted directories, cancellation, callback failure, scalar cursor coordinates, invalid ranges/prefixes, literal backslashes and regex punctuation, tilde filenames versus home expansion, newline/whitespace filenames, symlink cycles/aliases/broken links, FIFO exclusion, repository/global ignore behavior and invalid UTF-8 rejection. Bun and native one/four-thread execution are checked. The shared traversal extension also preserves all 85 public Find and 109 public Grep cases on all three backends.

## Explicit adaptations and remaining scope

- Locale collation is pending, consistent with the unresolved `ls` ordering choice. Callers must choose `ScalarOrder` or `FoldedScalarOrder`; neither silently becomes Pi's locale-sensitive default. Folded ordering/prefix matching use the existing Unicode case-fold tables, rather than JS lowercase/UTF-16 behavior.
- Cursor offsets, path lengths and string operations count native Unicode scalars. Invalid line/column/prefix edits return typed errors instead of JS slicing/coercion behavior.
- Directory classification, not the quoted completion value's final character, controls directory-first direct sorting. This corrects Pi's quoted-directory sorting bug.
- Native paths retain literal Unix backslashes, newlines and surrounding whitespace. Only `~` and `~/` expand to home; `~name` is an ordinary filename, correcting upstream's inconsistent directory/display handling. Windows path behavior remains unported.
- Attachment queries are literal, matching the final scorer's meaning. Pi passes bare queries through fd's regex parser first, causing literal regex punctuation to disappear or misfilter. The Bend implementation fixes that mismatch; none of the 27 named source tests require regex-query behavior. Queries beyond the existing runtime literal-regex compilation bound return a typed error.
- Bounded traversal selection is deterministic scalar directory order. Parallel fd can choose a different subset when more than 100 matches qualify. Direct-child priority and final ranking are preserved; exact scheduler-dependent over-limit subsets are not promised.
- Ordinary inaccessible/missing filesystem paths yield no suggestions as upstream does. Invalid encoded names/configuration, malformed ignore patterns and argument-callback failures remain typed failures rather than silent catch-all suppression.

Prefix/cursor scanning is linear and tail-recursive. Literal matching uses the existing regex runtime's literal matcher. Candidate storage is bounded to the two 100-entry passes, and their merge/ranking is bounded independently of tree size. The filesystem cursor additionally stores pending directory entries, ignore scopes and ancestry; a single directory is currently materialized by `FS.readDirectory`, so total traversal memory is not claimed to be constant. No compiler patch, production JS oracle or negative law test is introduced.

```sh
build/bend-native-toolchain/bend2/main.ts tests/autocomplete.bend -o build/autocomplete.js
BEND_TUS=8 sh scripts/build-pure.sh tests/autocomplete.bend build/autocomplete
python3 tests/autocomplete_check.py
```
