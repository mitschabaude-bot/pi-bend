# Native minimatch

`runtime/minimatch.bend` ports pi-mono's pinned `minimatch@10.2.6` with its dependency `brace-expansion@5.0.9` (and `balanced-match@4.0.4`), for default options on posix. `minimatch(path, pattern)` answers like upstream `minimatch(path, pattern)`; `tryMinimatch` returns `Fail{InvalidRegExp{source}}` where upstream's constructor throws, and `minimatch` answers False there. `compile(pattern)` plus `test(matcher, path)` reuse one compiled pattern (`new Minimatch(pattern).match(path)`), and `braceExpand(pattern)` is `minimatch.braceExpand`. No JavaScript, regex subprocess or foreign matcher participates in production.

The port follows the upstream pipeline: comment and empty patterns, `!` negation, the brace-set shortcut and brace-expansion (comma sets, nesting, escapes, `$` prefixes, the leading `{}` rule, numeric/alphabetic sequences with steps, padding and IEEE-754 number spelling, the 100,000-result bound), `/+` splitting, `levelOneOptimize`, the five fast portion checks, the extglob AST (parsing with `maxExtglobRecursion`, flattening by adoption/usurpation, `!` continuations, `toRegExpSource` with its dot and traversal guards), `parseClass` with POSIX classes, `unescape`, and `matchOne`/globstar body sections with `maxGlobstarRecursion` 200 and upstream's reversed bound computation. Patterns and paths are UTF-16 code units, since upstream's `?`, class members and `f.length` observe that width. Generated expressions are parsed as ECMAScript sources with the `u` flag exactly when upstream sets it, so the same escapes are rejected (for example `,`, `#`, `!` or a space next to a POSIX class) and surrogate pairs recombine under `u`. Matching computes reachable end positions, which is equivalent for these expressions (no backreferences; captures and laziness cannot change whether a match exists); repetitions add each position once. POSIX classes use `regex.bend`'s Unicode 17 tables; Bun 1.4 also implements Unicode 17.

Upstream mutates an AST whose flattening moves alternatives between nodes while `fillNegs` still appends to the lists of detached `!` nodes. The port keeps an immutable tree and records the observable consequences per node: alternatives' recorded parent indices, pending continuation counts from detached owners, and parse-time types. Doubly filled alternatives (`!(!(!(x)))y`), usurped negations and the literal text of empty whole-portion extglobs therefore match upstream.

Deliberate differences: a throwing pattern is a typed failure (and False from `minimatch`). brace-expansion counts its random-length escape sentinels toward the 4,000,000-character bound; the port counts one unit each, so only expansions near that bound can differ. The expression parser covers what minimatch generates; Annex B escapes it never emits (`\d`, backreferences, `{n}` quantifiers) are treated as literals. Options other than the defaults (`dot`, `nocase`, `matchBase`, `partial`, `windowsPathsNoEscape`, optimization levels) are not implemented.

## Validation

`minimatch_oracle.ts` runs the pinned upstream on 90,825 path/pattern pairs (22,273 true, 67,447 false, 1,105 throwing) and 5,485 `braceExpand` inputs: bash/minimatch-style hand cases crossed with edge paths (dots, `..`, empty and repeated slashes, trailing slashes, Unicode and astral scalars), each pattern's own expansions, seeded random patterns over glob/brace/extglob syntax with derived matching paths, nested extglob/negation shapes, multi-`**` patterns against deep paths, UTF-16 width cases, boundary probes of every POSIX-class Unicode range, long inputs (30,000-unit literals/classes/braces, 10,000 alternatives, 3,000-segment paths) and the globstar recursion cap at 150–250 sections. All results agree on Bun and optimized native one/four workers (about 2m45s, 18s and 18s).

```sh
bun build/bend-native-toolchain/bend2/main.ts tests/minimatch.bend -o build/minimatch.js
BEND_TUS=4 sh scripts/build-pure.sh tests/minimatch.bend build/minimatch
python3 tests/minimatch_check.py -- bun build/minimatch.js
python3 tests/minimatch_check.py -- build/minimatch --threads 1 --
python3 tests/minimatch_check.py -- build/minimatch --threads 4 --
```
