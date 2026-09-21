# Native resolver diagnostics

`packages/runtime/src/resolver-diagnostic.bend` presents resolver configuration failures without changing their acceptance policy. It retains file operation and OS code/message, environment-variable identity, invalid option tokens, transport-plan causes and UTF-8 byte positions. Option and environment names are JSON-quoted so quotes and line breaks remain unambiguous. The typed source report remains available separately; rendering does not reread files or inspect an environment.

The public `messages` function returns an immutable data list. Invalid options retain one message per diagnostic in their original order; callers choose how to present a collection. Loading and transport failures produce one message. An explicitly constructed invalid-options value with an empty diagnostic list stays empty, rather than inventing a cause. The system-provider initialization renderer still needs to compose these messages with entropy/owner-initialization failures.

[Nine generic laws](proof-validation/2026-09-21-resolver-diagnostic-standalone.json) include inductive proofs that option formatting preserves list length and concatenation. Additional contracts preserve arbitrary option tokens, OS codes/messages and typed loading/transport causes. Three type-correct mutants that drop options, erase a token or erase an OS code fail the intended laws. These proofs are standalone, outside the completed 522-law root. Three existing imported unsafe annotations appear; no new unsafe declaration was added.

All [45 finite runtime outcomes](runtime-validation/2026-09-21-resolver-diagnostic.json) pass across native one/four threads and Bun, including Unicode, embedded quotes/newlines, file/environment failures, invalid transport settings and UTF-8 positions. These native diagnostics have no pi/libc error-text equivalence claim. Source/program hashes and guarded build measurements are retained in the record; the native build includes both C generation and Clang-O1.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" sh scripts/build-pure.sh tests/resolver-diagnostic.bend build/resolver-diagnostic
bun build/bend-profiles/dns-transport-teles/bend2/main.ts tests/resolver-diagnostic.bend -o build/resolver-diagnostic.js
python3 tests/resolver_diagnostic_check.py
```

Proof integration update: the component laws are now included in the [552-law root check](proof-validation/2026-09-21-diagnostic-root.json), alongside 74 supporting lemmas. Earlier standalone counts and historical validation descriptions above do not limit their current registration.
