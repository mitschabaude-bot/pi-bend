# Native skill discovery

`packages/coding-agent/src/core/skills.bend` implements pinned `pi-mono@46c9de402` skill discovery, configured-location loading, metadata validation, canonical-file deduplication, first-name-wins collisions and prompt formatting. The public loader returns typed `Skill` values and `ResourceDiagnostic` values; filesystem effects are explicit `IO`. `loadSkills(environment, options)` receives the existing native path environment, and configuration supplies `agentDir` explicitly. The immutable work list performs depth-first discovery; one ordered ignore matcher follows the traversal, matching upstream rule precedence.

## Validation

```sh
npm install --ignore-scripts --no-audit --no-fund --prefix build/reference yaml@2.9.0 ignore@7.0.8
BEND=/path/to/bend2/main.ts
"$BEND" tests/skills.bend -o build/skills.js
python3 tests/skills_check.py -- bun build/skills.js
BEND="$BEND" BEND_TUS=8 sh scripts/build-pure.sh tests/skills.bend build/skills
python3 tests/skills_check.py -- build/skills --threads 1
python3 tests/skills_check.py -- build/skills --threads 4
```

Final source passed Bun and optimized native execution with explicit one/four workers: 37 complete loader comparisons and seven native policy cases on each backend.

The compiler must include `patches/bend-directory-metadata.patch` and the earlier filesystem/path effects. The test host evaluates the actual pinned source and all 28 named `skills.test.ts` assertions under Node. It compares the 23 loader invocations captured by those assertions and 14 additional filesystem scenarios against complete Bend results, preserving skill/diagnostic order and all source/collision metadata. Seven original pure formatting assertions also have direct Bend coverage in [system-prompt.md](system-prompt.md); the loader fixture does not relabel Node-only formatting execution as new Bend coverage.

Additional scenarios cover actual user/project/explicit collisions (the original collision test simulates a Map), canonical duplicate files through symlinks, source scopes with defaults disabled, relative/tilde/file-URL inputs, missing/non-Markdown/FIFO paths, root `SKILL.md` precedence including invalid roots, direct root Markdown versus nested discovery, ignored dot directories/node_modules, broken/file/directory symlinks, all three ignore filenames and their ordering, nested ignore prefixes, ignored root skills, BOM/CRLF, block descriptions, indentless metadata sequences and ASCII description boundaries. All trees live under temporary directories; neither the process HOME nor real account directories are changed. FIFOs ensure discovery never opens nonregular candidate content.

Node's directory enumeration sorts entries, whereas Bun's enumeration preserves the OS order on this host. Therefore the reference runs the transpiled pinned source using Node's actual filesystem functions; Bend explicitly sorts entries. No test sorts results after loading or erases collision order. Parser diagnostic prose/source spans are the only normalization in the differential comparison.

## Deliberate native behavior

Seven focused cases exercise these approved policies:

- Reject nonstring names/descriptions and nonboolean `disable-model-invocation` with typed warning diagnostics; upstream falls back or ignores malformed metadata. Missing and empty string names still use the directory basename, and name warnings still permit a skill with a valid description.
- Reject malformed UTF-8 rather than silently replacing bytes.
- Count Unicode scalar characters, rather than JavaScript UTF-16 code units, for validation limits. A 1,024-emoji description is within the native limit.
- Stop a directory symlink cycle at its canonical ancestor and report it, instead of repeated traversal until an OS error.
- Preserve the escape in a root `\!literal` ignore rule. Upstream's prefix helper strips it and accidentally changes exclusion into negation; native behavior follows Git's literal-exclamation rule.

None of these changes alters a pinned named assertion. Directory/ignore-read errors are reported as warnings instead of upstream's silent catch; broken candidate symlinks remain skipped. Known-invalid ignore patterns retain a diagnostic rather than disappearing silently. Existing ignore matcher corrections are described in [ignore.md](ignore.md). YAML parser errors keep native source locations and prose, not JavaScript exception formatting.

The loader is implemented; resource-loader/CLI wiring belongs to their respective modules. This milestone does not claim complete YAML dependency parity: remaining grammar and validation coverage are explicit in [frontmatter.md](frontmatter.md). No host YAML, ignore or filesystem library supplies production policy.
