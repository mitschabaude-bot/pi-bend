# Native path glob matching

`runtime/path-glob.bend` implements fd-style basename/full-path glob syntax: separator-aware `*`/`?`, recursive `**`, character classes and ranges, escaping, nonnested brace alternatives and smart case. The parser emits a linear program; matching keeps one reachability bit per program boundary and a brace-frame stack. Alternatives never expand into a Cartesian product. Fixed-width patterns use a direct linear scan. Wildcard matching takes O(pattern size × text length) time and O(pattern size) state, independently of the number of possible brace combinations. These are algorithmic bounds, not claimed Bend proofs.

The test-only oracle uses `globset=0.4.16`, `regex=1.11.1`, `regex-syntax=0.8.5`, and the verified helper source from [fd 10.3.0](https://github.com/sharkdp/fd/blob/v10.3.0/src/regex_helper.rs). Its setup script downloads and hashes the helper into ignored `build/`; no Rust or other host implementation is used by production. All 13,068 differential cases pass on Bun and O1 native one/four workers, plus nine malformed inputs, nine explicit Unicode contracts, a 40-group pattern with 2^40 potential combinations, a 20,000-character fixed pattern and a 10,000-component recursive path.

Native strings use Unicode scalars: `?` consumes one scalar, and insensitive literal/class matching uses Unicode 17 simple-fold equivalence. fd's glob regex disables Unicode and counts UTF-8 bytes; it also folds only ASCII in that mode. Thus native `?` matches `é` and `😀`, and native lowercase `é` matches `É`. Uppercase smart-case literals still select exact matching. Character classes test all equivalent scalars before negation, rather than folding range endpoints. The differential corpus uses ASCII to isolate matching syntax and state transitions; Unicode cases assert the explicitly approved native behavior. The generated `case-fold.isUppercase` data is independently checked exhaustively against Unicode's official derived property.

Malformed braces/classes/ranges and dangling escapes return typed errors. Stray closing braces are rejected rather than silently discarded by globset. Empty brace alternatives follow globset's actual parsing behavior. This module is a reusable matcher, not the tool's basename/full-path selection or filesystem ignore policy; those belong to `find.bend`.

```sh
python3 tests/path_glob_reference.py
BEND=/path/to/private/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/path-glob.bend build/path-glob
/path/to/private/bend2/main.ts tests/path-glob.bend -o build/path-glob.js
python3 tests/path_glob_check.py bun native-1 native-4
```
