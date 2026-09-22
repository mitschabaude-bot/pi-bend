# Application keybindings

`packages/coding-agent/src/core/keybindings.bend` supplies application defaults, legacy-name migration, effective configuration and file-backed manager creation/reload on top of the native TUI manager. `Environment` makes platform and WSL facts explicit; Windows Terminal detection is intentionally unrelated to Windows keybinding selection. Typed immutable managers replace hidden global state and mutable inheritance.

## Pinned tests and scope

The reference executes the actual pi-mono `46c9de402` test bodies and assertions. All five `keybindings.test.ts` cases are exercised:

- `uses Windows keybindings on native Windows`
- `uses Windows keybindings in WSL without relying on Windows Terminal detection`
- `does not use Windows keybindings from WT_SESSION alone`
- `keeps non-Windows defaults on other platforms`
- `applies the detected defaults consistently`

The migration reference also executes all three `keybindings-migration.test.ts` cases. Its `runMigrations` adapter invokes the actual source `migrateKeybindingsConfigFile` body, isolating that responsibility from unrelated auth/session/tool migrations. Native coverage is intentionally distinguished:

- `rewrites old key names to namespaced ids`: pure transformation covered; migration file-rewrite orchestration remains pending.
- `keeps the namespaced value when old and new names both exist`: precedence covered in both insertion orders; migration file-rewrite orchestration remains pending.
- `loads old key names in memory before the file is rewritten`: actual native file creation/loading, migrated user configuration and full effective configuration covered. Loading itself does not rewrite the file.

The source trace contains 18 observations across these eight named tests; these are not claimed as 18 independent original assertions. Default-property access is captured as the full definitions snapshot, and original assertions still execute against the unmodified source values. Canonical modifier spelling and scalar/list presentation are normalized to typed key lists, as in `tests/keybindings.md`.

## Additional coverage

The corpus checks 36 platform/WSL combinations, including missing and empty environment strings, every migration alias, canonical-name precedence in both insertion orders, randomized mixed migration values, all default descriptions and full effective configurations. Migration retains arbitrary JSON values without prematurely validating them; file decoding subsequently validates the binding schema and identifiers. Unknown actions remain preserved in configuration and do not become effective bindings.

Real temporary-directory tests cover missing files, BOM, legacy names, empty/unknown configuration, malformed JSON, non-object roots, wrong binding types, invalid key identifiers, duplicate fields (canonical parser last-wins behavior), invalid UTF-8 and a directory where a file is expected. Same-process reload tests change the file between calls and verify replacement, restoration of defaults, typed failures, and continued usability of the retained old immutable manager. No real user settings, home directory or parent environment are changed.

Strict malformed-file rejection is an intentional adaptation: upstream ignores malformed files or individual values and silently resets defaults on failed reload. Native errors make the failure explicit, and callers retain their existing manager. Missing files still mean empty user configuration. Semantic key identity corrections are documented by the underlying keyboard and TUI manager fixtures.

## Reproduction

```sh
bun build/bend-process-files/bend2/main.ts tests/app-keybindings.bend -o build/app-keybindings-field.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/app-keybindings.bend build/app-keybindings-field
python3 tests/app-keybindings_check.py -- bun build/app-keybindings-field.js
python3 tests/app-keybindings_check.py -- build/app-keybindings-field --threads 1
python3 tests/app-keybindings_check.py -- build/app-keybindings-field --threads 4
```

The Bend fixture uses JSON only for test transport; production remains typed native Bend. Bun and optimized native explicit one/four threads pass all 18 original-source observations, 516 platform/default/migration/manager comparisons, 13 real-file cases and four reload/retained-state cases. The differential corpus caught Darwin tree-navigation default ordering, which was corrected before final validation.

During fixture construction, importing the earlier `tests/keybindings.bend` helper module failed parsing its `R.Property{name,keys}` binder as the defined global `keybindings.keys`; the standalone fixture compiles. Keeping transport helpers local avoids that test-module name collision. Production code and compiler were unchanged.

Checked production source SHA-256: `a4dcaf11fca054747f711a756c23875c52a3438f00eb058635123f38d15212f3`; fixture SHA-256: `7859748fb0547183cedefcc44a3a9bb8bca1c7e7b40b714f7bf9c13e27e58506`.
