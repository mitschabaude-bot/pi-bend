# Fuzzy search

`packages/tui/src/fuzzy.bend` ports the public `fuzzyMatch` and generic `fuzzyFilter` functions from pi 0.85.1. The scan retains the original arithmetic order, consecutive and word-boundary bonuses, gap and position penalties, exact-match bonus, and fallback swapping of two ASCII letter/digit blocks. Filtering requires every whitespace/slash-delimited token and stably ranks by summed score. Empty queries preserve input order and typed items.

`fuzzy_reference.mts` executes all 14 original named tests against the pinned TypeScript source, retaining their assertions and recording 18 public calls. The checker compares those calls and generated cases: 1,988 comparisons total, with binary64 score equality and exact selected item order. Four native Unicode cases and long-input checks supplement the upstream oracle. All checks pass on Bun and O1 native with one and four workers.

Native strings use Unicode scalar positions and Unicode simple case folding. This deliberately avoids UTF16 surrogate positions and JavaScript contextual lowercasing: supplementary characters count once, and simple-fold equivalents such as Greek sigma match. ASCII scoring agrees exactly with upstream. This is runtime/differential evidence, not a claim of proved laws or completed selectors/model listing.

```sh
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/fuzzy.bend build/fuzzy
build/bend-process-files/bend2/main.ts tests/fuzzy.bend -o build/fuzzy.js
python3 tests/fuzzy_check.py
```
