# Native Unicode collation (`localeCompare`)

`packages/runtime/src/collation.bend` reproduces `String.prototype.localeCompare` exactly as pi's reference runtime evaluates it: Node 24.18, ICU 78.3, Unicode 17, CLDR 48, default locale `en-US`, default options (tertiary strength, non-ignorable punctuation, no backwards secondary, case-first off, numeric off). V8 turns on ICU's normalization mode (ECMA-402 canonical equivalence), so `Intl.Collator('en-US').compare` gives the same results.

API: `load(directory)` reads `icu78-collation.bin` from the installed data directory (`packages/runtime/data`) and returns a typed `Result<LoadError, Collator>`. `compare(collator, left, right) -> Cmp` (also exported as `localeCompare`) gives the sign of `left.localeCompare(right)`. `key(collator, text)` computes a reusable `Key` once and `compareKeys` compares two keys, so sorting n strings costs n key computations, not n log n. `sort(collator, strings)` is a stable key sort that gives the exact order of `strings.sort((a, b) => a.localeCompare(b))`. `keyCodes` accepts UTF-16 code units or code points, as a JavaScript string does. It pairs adjacent high/low surrogates and keeps lone surrogates. Bend `Char`s cannot hold surrogates on the JS lane.

## Exact behaviour and data

Weights come from ICU 78.3's `FractionalUCA.txt`, which ICU builds its CLDR 48 root collator from. `scripts/generate-collation.py` pins it by URL and SHA-256 and uses the pinned Unicode 17 UCD for canonical decompositions and combining classes. The generator re-ranks primary, secondary and tertiary weights densely, masking the tertiary case bits as ICU does when case-first is off. It writes the 356,921-byte `packages/runtime/data/icu78-collation.bin` and its manifest. The data are covered by the Unicode License V3 (`icu78-cjk.LICENSE`, the ICU 78 license text). `python3 scripts/generate-collation.py --check` verifies the checked-in asset. The file contains 10,997 mappings (8,615 of them runs of consecutive weights), 76 contraction starters with 1,149 suffixes, the `L|·` prefix rules, Han in radical-stroke order (101,996 ideographs in 20,546 spans), and the NFD/FCD tables. The module loads it at run time rather than compiling tables into C.

`allkeys_CLDR.txt` (UCA 17, byte-identical to CLDR `release-48/common/uca/allkeys_CLDR.txt`) is not ICU's table. It orders Han by implicit code-point weights, whereas ICU root uses radical-stroke order. It also differs in the Tangut component and supplement order, and it lacks ICU's `U+FDD1` script-boundary contractions and closure contractions such as Gurung Khema `1611E 16123`. Plain UCA with this table (NFD, S2.1 discontiguous matching) disagrees with Node on 3,985 corpus pairs (0.6%).

The engine ports ICU's `FCDUTF16CollationIterator` and `CollationIterator` contraction matching, including observable quirks rather than an idealised NFD model:
- FCD input is collated unnormalized. For example, `113C2 113C5` and `113C5 113C2` differ even though both are canonically equivalent to `113C2 113C2 113C2`.
- Non-FCD segments are NFD-normalized and Tibetan composite vowels are always normalized. Discontiguous contractions follow ICU's `prevCC < lccc` rule, its skipped-mark buffer and its replay.
- A backward move re-segments text with ICU's unit-level fast path, where a trail surrogate never has tccc. Contraction look-ahead that backs up over a supplementary mark followed by a lower-class BMP mark therefore re-reads that run raw.
- When a composite mark such as U+0344 is counted differently in the two directions, the back-up passes the contraction starter and ICU emits the starter's weights forever: `"ླۙ\u{10A0D}̈́Ừ"` sorts after `"ླ".repeat(500)` and before the same run followed by `ྴ`. Keys detect repeated iterator states with Brent's algorithm and represent such streams as a prefix plus a repeating cycle. Comparison follows ICU wherever ICU terminates.
- Lone surrogates, unassigned code points, noncharacters and U+FDD0 get ICU's unassigned implicit weights, ordered after Han. `U+FFFD`/`U+FFFF` are the trailing weights, and `U+FFFE` is the lowest primary. Hangul syllables collate as conjoining jamo. `U+0000` and other controls are ignorable.

Residual difference: if two strings' primary weights agree forever (both repeat identical cycles), ICU never returns; here they compare `EQ`. The corpus found no other difference.

## Scope

Only root collation is implemented. It is the result under `en-US`, any other `en` locale, `und`, `C`/`POSIX`/`C.UTF-8`, and every locale whose CLDR collation is root, such as `de`, `fr`, `it`, `nl` and `pt`. Locale tailorings are not included: Swedish, Danish/Norwegian, Finnish, Spanish traditional, German phonebook, Polish, Czech, Turkish, Japanese, Chinese pinyin/stroke, Korean and so on. So are the `numeric`, `caseFirst`, `sensitivity`, `ignorePunctuation` and collation-type options. `localeCompare` without a locale uses Node's default locale, which ICU takes from `LC_ALL`, then `LC_MESSAGES`, then `LANG` (`LC_COLLATE` is ignored). Under `LANG=sv_SE.UTF-8`, for example, pi would order `z` before `ä`; this module keeps root order. A tailored port would need to select the locale the same way and add the CLDR tailoring rules.

Performance: native builds need about 14 µs per key on the corpus (1.34 M keys in 19 s), and loading the data takes about 30 ms. The Bun lane is about four times slower. Work is linear in the input: a 200,000-code-point comparison takes 1.2 s natively. NFD runs use a merge sort, and neither the skipped-mark buffer nor any region copy recurses deeply. The test program generates 1.37 MB of C, about 1.24 MB for this module; a file-reading baseline is 0.13 MB. `BEND_TUS=4` builds take about 5 s, and single-unit builds take 8.5 s. The code avoids feeding `Bool.pick` results to `&&`/`||`, a known native miscompilation (`tests/repro/bool-pick-or.bend`).

## Differential test

`tests/collation_reference.mjs` runs under plain `node`, because Bun's ICU may differ. It asserts ICU 78.3/Unicode 17/CLDR 48 and the default locale `en-US`, and checks that `localeCompare`, `Intl.Collator.compare` and the reversed comparison agree. It writes 669,679 pairs with their signs:
- every BMP code point (including unassigned code points, lone surrogates and noncharacters) against its code-point neighbour and its collation neighbour
- every assigned supplementary code point outside the sampled implicit blocks, again against its collation neighbour
- whole-code-space samples at implicit/unassigned/private-use edges
- mixed scripts, case and diacritics, digits, punctuation and symbols
- contraction families (Thai/Lao/Tai Viet/New Tai Lue prevowels, Tibetan, Cyrillic, Arabic, Indic two-part vowels, Tulu-Tigalari, Gurung Khema, Kirat Rai)
- every canonical composite before marks of each class, in canonical and non-canonical order
- `U+FDD0`/`U+FDD1` boundaries and `L·`
- Hangul syllables against jamo, and emoji/ZWJ sequences
- file-name-like strings (`file9`/`file10`, dots, dashes, underscores, case variants lowercased as `ls` does)
- empty strings, ignorables and prefixes
- lone surrogates, and surrogate pairs given as separate units
- 60,000 adversarial non-FCD strings
- 12,000 starter, mark and U+0344 comparisons, 2,784 of them with the infinite streams described above (645 distinct strings)

It also writes 4,000 strings and the stable order Node's `Array.prototype.sort` gives them. The Bend runner uses `compare`/`sort` on strings and `keyCodes` where surrogates are involved.

```sh
bun build/bend-native-toolchain/bend2/main.ts tests/collation.bend -o build/collation.js
BEND_TUS=4 sh scripts/build-pure.sh tests/collation.bend build/collation
python3 tests/collation_check.py            # bun, native-1, native-4
```

All 669,679 signs and the 4,000-string order match Node on Bun and on native one/four threads. During development, a Python model of the same port also matched 900,000 further random adversarial pairs and 5,536 cycle cases against Node.
