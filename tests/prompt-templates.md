# Prompt templates

`core/prompt-templates.bend` ports the pure argument parser, substitution and expansion from pinned Pi `46c9de402`, `packages/coding-agent/src/core/prompt-templates.ts`. Loading and its frontmatter assertions remain pending in this milestone.

The test-only oracle executes the original suite's pure assertions and captures all 127 calls to the three public functions. It then compares these and 436 additional calls against Bend, including positional defaults, argument slices, zero and very large indices, literal placeholder text inside replacements, Unicode whitespace, multiline commands, first matching template precedence and unknown commands. All 563 comparisons pass Bun and optimized native execution with explicit one and four workers. Eight unfinished-quote cases return typed errors. In-core 200KB literal replacement and 200KB unfinished-default inputs also pass all three backends.

Unclosed argument quotes are rejected with `UnclosedQuote`; upstream silently accepts the rest of the input. Empty quoted arguments are omitted, as the original suite explicitly requires. Backslashes remain literal; this parser is not a shell interpreter. Unrecognized placeholder syntax remains ordinary template text. Replacement values and defaults never reenter the scanner. Numeric indices saturate at one beyond the argument count, preserving out-of-range and slicing behavior without floating-point rounding or overflowing integers.

The scanner processes template text and replacement output with tail-recursive accumulators. After the first failed default scan, it remembers that no closing brace remains, avoiding quadratic rescanning of many unfinished defaults. Positional lookup and slicing traverse the argument list; joined all-argument text is computed once. This is not a claim that arbitrary repeated indexed lookups take constant time.

Run:

```sh
build/bend-native-toolchain/bend2/main.ts tests/prompt-templates.bend -o build/prompt-templates.js
sh scripts/build-pure.sh tests/prompt-templates.bend build/prompt-templates
python3 tests/prompt_templates_check.py --runner build/prompt-templates.js
python3 tests/prompt_templates_check.py --runner build/prompt-templates --threads 1
python3 tests/prompt_templates_check.py --runner build/prompt-templates --threads 4
```
