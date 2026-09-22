# Native ignore rules

`runtime/ignore.bend` implements immutable ordered ignore rules for skill discovery. `empty` uses case-insensitive Unicode scalar matching; `new(False{})` selects case-sensitive matching. `add` accepts individual lines, `addText` accepts an ignore file, and both return a new matcher or a typed pattern error. `test` returns `Decision{ignored,unignored}`; `ignores` returns the ignored flag. Queries require normalized relative paths, with a trailing slash identifying a directory. `errorMessage` renders either error type. No filesystem, regular-expression engine, JavaScript or foreign matching implementation participates in production.

Rules support comments, escaped initial `#`/`!`, ordered negation, root anchoring, directory-only patterns, basename matching at arbitrary depth, `?`, ordinary stars, recursive `**` components, escaped characters/spaces, ranges, leading literal bracket members, both bracket negation forms, and all twelve ASCII POSIX classes. Bracket-aware parsing keeps slashes inside ranges separate from path separators. Excluded ancestors remain excluded even if a later rule would reopen a descendant; reopening the parent first works. Leading BOMs and CRLF files are accepted.

The matcher reuses the existing glob token grammar. Scalar and path-component matching use boolean state rows, avoiding exponential backtracking. Fixed-width components take a direct linear scan; star-bearing components take time proportional to token count times text length and keep one state row. Ancestor queries currently rescan prefixes, so very deep paths can take quadratic time in path depth. Case folding tests equivalent scalars against original range endpoints before class negation. Unicode data and its exhaustive validation are described in [case-fold.md](case-fold.md).

## Validation and deliberate differences

The differential harness compares 8,907 rule/path results against pi's pinned `ignore@7.0.8`, including ordered multi-rule cases, seeded patterns, escaped spaces/slashes and every ASCII POSIX class. Bun and optimized native one/four workers pass, alongside fourteen strict malformed-input rejections, five long/adversarial cases and nineteen Unicode literal/class/scalar-width cases. Long inputs include 30,000-scalar literals and star matches, a 300-wildcard nonmatch and a 1,000-component path. These are executed comparisons, not general Bend proofs.

Three discovered differences correct a confirmed bug in `ignore@7.0.8`'s `pinWildcards` optimization. The harness independently checks all three with `git check-ignore --no-index`: `****b/****b/` excludes `bb/ab.b/b/b`, `/*******[ab]/a**` excludes `ba.b/a./a.a/...a`, and `*?b**a` excludes `aa/a/a..a/a.ba`. The JavaScript dependency incorrectly includes them. Bend retains Git's behavior, so discovery skips paths that these patterns were intended to exclude.

Malformed bracket expressions, reversed ranges, unknown POSIX classes and dangling escapes return errors instead of becoming ineffective patterns or partially matching. Empty, absolute, dot-component and repeated-separator query paths are rejected instead of guessing a normalization. Unicode matching uses scalars and default simple-fold equivalence: `?` consumes one supplementary scalar, and case-insensitive literals/classes recognize Kelvin sign, long s, sharp S and supplementary case pairs. Legacy JavaScript `/i` does not recognize all of these; neither its UTF-16 width nor its case limitations are reproduced. No locale-dependent or multi-character case expansion is performed.

This ports the matching operations needed by the resource loaders. The upstream package's separate `checkIgnore` diagnostic mode, rule-provenance reporting and convenience filtering APIs are not yet exposed. Its mutable caches and object identity are not native API requirements. Full skill-discovery parity additionally depends on the loader and filesystem/frontmatter modules; this fixture does not claim that integration complete.

```sh
mkdir -p build/ignore-reference
npm pack ignore@7.0.8 --pack-destination build/ignore-reference
tar -xf build/ignore-reference/ignore-7.0.8.tgz -C build/ignore-reference
BEND=build/bend-process-files/bend2/main.ts
"$BEND" tests/ignore.bend -o build/ignore.js
BEND="$BEND" BEND_TUS=8 sh scripts/build-pure.sh tests/ignore.bend build/ignore
python3 tests/ignore_check.py -- bun build/ignore.js -- --
python3 tests/ignore_check.py -- build/ignore --threads 1 --
python3 tests/ignore_check.py -- build/ignore --threads 4 --
```
