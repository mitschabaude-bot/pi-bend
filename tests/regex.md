# Native regular-expression matching

`runtime/regex.bend` supplies boolean Unicode-scalar matching for the native grep dependency. It parses concatenation, alternation, capturing/named/noncapturing groups, scoped flags, bounded/unbounded/lazy repetition, anchors and word-boundary variants, hexadecimal escapes, nested classes, ASCII classes, set intersection/subtraction/symmetric difference, and Unicode properties. Names are validated and duplicate capture names rejected; captures are not returned because grep needs matching lines, not submatch extraction. The compiled program has an explicit 65,536-state budget and groups have a 250-level nesting budget. Invalid patterns and exceeded budgets return typed errors.

The core is a Thompson NFA: each state is visited once at each input boundary, including epsilon cycles from nullable repetitions. Compiler and class-expression evaluation use explicit work stacks. Exact literals and fixed literal repetitions use KMP, with linear comparison counts and immutable indexed prefix-table lookup. This prevents repeated literal prefixes from producing a quadratic frontier. The shared `u32-table` constructor builds balanced tables from strictly sorted unique entries; replacement preserves the key set and balance. No production regex subprocess or foreign matcher supplies behavior.

Unicode properties come from the official Unicode 17 UCD archive, pinned by SHA-256 in `scripts/generate-regex-unicode.py`, under the existing Unicode license. The generated module holds compact interval payloads and aliases; only requested property intervals are decoded when compiling a pattern. It covers general categories, scripts/script extensions, ages, segmentation properties, binary properties and the Unicode word class. Case-insensitive matching uses the existing Unicode 17 simple-fold equivalence. The external test oracle uses `regex=1.13.1`, `regex-automata=0.4.18`, and `regex-syntax=0.8.11`; these still embed Unicode 16. Eight separate checks cover independently identified Unicode 17 additions.

The scalar API does **not** redefine byte matching: byte-consuming `(?-u)` constructs return `RequiresByteInput`. Safe ASCII classes, ASCII boundaries/case folding and complete scalar literals remain usable. A byte-input matcher supporting mixed Unicode and byte transitions is still required for full ripgrep dependency parity. Streaming matcher state, grep's file traversal/decoding/binary policy, line/context formatting and the public grep tool remain pending. Verbose-mode comments inside escape/count syntax also still need complete reference coverage; this is not a claim that all Rust regex syntax is ported.

The focused runner compares 23,064 matching/rejection results against Rust, reports byte-input rejections separately, exercises long literals/classes/alternations/repetitions and nullable loops, and checks indexed-table construction, floor lookup, replacement and missing-key preservation across 16,385 entries. A 12,000-character repeated-literal Bun check that previously exceeded 60 seconds completes in about 0.24 seconds with KMP; this includes process startup and fixture handling, not just matching. All checks pass on Bun and O1 native one/four workers. The eight long/adversarial cases together take about 1.61 seconds on Bun and 0.24/0.28 seconds on native one/four in the fixture.

```sh
python3 tests/regex_reference.py
python3 scripts/generate-regex-unicode.py
/path/to/private/bend2/main.ts tests/regex.bend -o build/regex.js
BEND=/path/to/private/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/regex.bend build/regex
python3 tests/regex_check.py bun native-1 native-4
```

Integration validation rebuilt this fixture with `build/bend-process-files/bend2/main.ts` and reran the complete corpus on Bun/native one/four. Each passed 23,064 Rust comparisons, 439 explicit byte-input rejections, eight Unicode 17 checks, eight long/adversarial cases, and 131,101 table checks. The long cases took 1.600/0.275/0.288 seconds respectively; these fixture timings are not a general regex performance claim.
