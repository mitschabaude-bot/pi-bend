# Native keybindings manager

The pure `packages/tui/src/keybindings.bend` ports pinned pi-mono `46c9de402`'s `packages/tui/src/keybindings.ts`. `KeybindingsManager` is an immutable value built by `create(definitions, userBindings)`; `setUserBindings` returns a replacement manager. The owning UI passes this value explicitly instead of using `setKeybindings`/`getKeybindings` process globals. `matches` also receives the keyboard's immutable `Context`.

Definitions and bindings use immutable records keyed by extensible action names. Native key lists replace the source's scalar-or-array union; missing actions use defaults, an explicit empty list unbinds, and unknown actions remain in the user configuration but never resolve or claim conflicts. Definition descriptions remain optional; unknown `getDefinition` returns `None`. All defaults and descriptions are covered by actual-source comparisons. Shared default bindings remain available even when another action claims the same key; conflicts concern direct user claims only.

## Upstream test mapping

`tests/keybindings_reference.ts` executes the actual original test file, using Node assertions and a traced subclass of the actual source manager. Every asserted getter/matching result is captured with its full test name and replayed against Bend. All seven named tests (29 assertions) are covered:

- `binds Ctrl+J as a default newline alias`
- `binds modified and unmodified editor viewport navigation`
- `leaves dedicated prompt history navigation unbound by default`
- `binds unmodified terminal viewport shortcuts to alternate-screen navigation`
- `does not evict selector confirm when input submit is rebound`
- `does not evict cursor bindings when another action reuses the same key`
- `still reports direct user binding conflicts without evicting defaults`

The oracle normalizes only key identifier spelling and scalar/list representation for normal differential comparisons. In particular, `ctrl+shift+up` and native canonical `shift+ctrl+up` mean the same typed key. It does not substitute a rewritten manager algorithm for the source.

## Additional contracts and adaptation

The corpus runs 31,589 source query comparisons across 152 managers. It covers every default/description, custom definitions, unknown actions, empty lists, exact duplicate removal, user-only conflicts, retained unknown configuration, replacement rather than merging, restoring defaults, and conflict clearing. Matching exercises actual control/legacy/Kitty/modifyOtherKeys inputs across both Kitty and Windows context flags.

Typed identities deliberately make deduplication and conflict reporting semantic. Upstream's string set treats `ctrl+shift+x` and `shift+ctrl+x` as distinct claims despite matching the same event; native bindings collapse them and report a conflict when different actions use those spellings. Likewise `esc` and `escape` collapse. A separate adaptation case verifies native expectations and confirms that the unmodified source differs, rather than hiding the correction in oracle normalization. No original named assertion changes its meaningful expectation.

The fixture accepts JSON solely for test transport. Production APIs require already validated `Keys.KeyId` values; keyboard identifier rejection and protocol boundary coverage live in `tests/keys.md`. Tests do not recreate undefined-valued object properties, prototype inheritance or mutable getter aliasing.

## Reproduction

```sh
bun build/bend-process-files/bend2/main.ts tests/keybindings.bend -o build/keybindings-field.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/keybindings.bend build/keybindings-field
python3 tests/keybindings_check.py -- bun build/keybindings-field.js
python3 tests/keybindings_check.py -- build/keybindings-field --threads 1
python3 tests/keybindings_check.py -- build/keybindings-field --threads 4
```

Validation uses the existing combined compiler and normal optimized native build. No compiler or production source changes are part of this fixture handoff; no trivial laws or negative proof tests were added.

Final result: Bun and optimized native explicit one/four threads all pass the complete corpus above. Checked production source SHA-256: `8b18ef30906947c36a2bdcee6ff76876ec8c91420e79415158c1f55cd5405366`; Bend fixture SHA-256: `9139f7f38574d7749e4bd93882a7414dd70a8b4172efdcf1d93e6dfe623d91db`.
