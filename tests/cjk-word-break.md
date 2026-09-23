# Native ICU78 CJK dictionary segmentation

`runtime/cjk-word-break.bend` implements ICU 78.3 `CjkBreakEngine::divideUpDictionaryRange` in word mode for an explicitly supplied dictionary range. It uses the complete weighted Chinese/Japanese dictionary, NFKC normalization with source-offset mapping, and the original Katakana heuristic. Production loading, matching, normalization and segmentation are pure Bend. This is not yet Pi's complete `Intl.Segmenter` default: outer ICU word-rule matching/range selection and lexical status are separate dependencies, as are Thai/Burmese LSTM and Lao/Khmer dictionary engines. Phrase-mode segmentation is outside this word-navigation dependency.

## Interface and representation

Read `packages/runtime/data/icu78-cjk.bin` through the existing filesystem interface, call `cjk-dictionary.decode`, then call `cjk-word-break.create` once. The resulting immutable `Context` contains the radix dictionary and existing native Unicode normalization tables. `boundaries(context, text)` returns strictly increasing source-scalar endpoints, including the range end for nonempty input. `handles(char)` exposes the exact CJK engine character set for future ICU rule dispatch. Callers must supply whole dictionary ranges; individually feeding the Han regions from default UAX segmentation would lose dictionary words spanning those boundaries.

The pinned source contains 315,964 distinct entries, costs 27–251, and words up to 16 scalars. All dictionary scalars happen to be BMP; the generator verifies that condition rather than truncating scalars. The serialized radix trie contains 330,447 nodes in 2,204,725 bytes. Fixed-width postorder records store a terminal cost (255 means absent), child count and compressed UTF-16 labels. The pure decoder validates the pinned header, record boundaries, scalar validity, descending child-key order, stack shape and complete consumption, then constructs balanced immutable child tables. No dictionary-sized Bend constructor source is compiled. Supplementary input remains supported and follows ICU's unknown-character rule when no dictionary word matches.

The dynamic program preserves ICU's match order, strict-less cost updates, 20-scalar search bound, cost-255 single-character fallback (except Hangul), Katakana cost table, and the strict run-length `<20` cutoff. A rolling 21-slot immutable window suffices because every edge is bounded by 20 scalars. Cumulative path costs use checked native `Nat`, with `None` as infinity, so scores beyond U32 retain their ordering instead of wrapping. The installed compiler bounds Nat at 2^48−1 and rejects arithmetic overflow; this is wider checked arithmetic, not an arbitrary-precision claim. This is an intentional long-input correctness improvement. Winning candidates share persistent predecessor paths; no full-length mutable score table or quadratic prefix rescans are required.

## Normalization offsets

Already normalized input preserves identity scalar offsets. Otherwise, the engine splits at exact NFKC `hasBoundaryBefore` positions, normalizes each fragment using the existing native tables, maps every scalar in that normalized fragment to its original fragment start, and maps the terminal endpoint to the source end. Projected duplicate boundaries inside expansions are removed, matching ICU's handling of ticket #12918. This preserves boundaries for both contraction (for example halfwidth voiced Kana) and expansion without slicing original text at normalized coordinates.

The boundary-before predicate is derived from the recursively decomposed first scalar: it must have canonical combining class zero and must not combine backward through a canonical composition pair or Hangul V/T. A test-only N-API oracle calls `unorm2_hasBoundaryBefore_78` exported by the installed Node binary; the derived predicate agrees for all 1,114,112 code points. The addon supplies no production behavior. The CJK character-set predicate uses pinned Unicode17 Script properties and ICU's four explicit additions.

## Validation

`tests/cjk_dictionary_check.py` checks 315,968 exact complete prefix-match lists on Bun and native one/four threads: every dictionary word and all of its weighted dictionary prefixes, plus empty, supplementary and composite inputs. Expected values come directly from the pinned textual dictionary, independently of the packed asset. The generator additionally reconstructs every word/cost from the serialized bytes and verifies exact equality before writing or checking the asset. The dictionary fixture uses TSV and a single final result, avoiding hundreds of thousands of separate hosted output effects; the first per-row JSON/output harness exceeded its 120-second budget and was replaced without reducing the corpus or expectations.

`tests/cjk_word_break_check.py` compares 2,151 exact boundary lists against Node's pinned ICU 78.3 / Unicode 17.0 `Intl.Segmenter`: directed Chinese/Japanese examples, 1,024 dictionary words, 1,024 random compound inputs, Katakana lengths around 19/20, halfwidth voiced Kana, compatibility ideographs, compatibility expansions, supplementary Han, and five long cases up to 22,000 scalars. The long cases include normalized Japanese, Katakana, halfwidth contraction, supplementary fallback and compatibility ideographs. All pass Bun and native one/four threads. Each case also checks invariance under a starting score of 4,294,967,200, crossing the old U32 boundary without changing any optimum. Example aggregate runs, including dictionary load and all five long cases, took 5.342 seconds on Bun and 0.481/0.575 seconds native one/four; these are shared-host observations, not isolated throughput benchmarks.

The first long normalized-input run reproduced the already documented Base `String.eq` stack overflow from BEND-019 (see `docs/bend-issues.md`, “large edit prefixes”). Reusing the existing tail-recursive `runtime/string.equal` resolved this caller; no compiler or Base patch was made. Generic weighted-optimality, partition and offset-preservation proofs remain unproved; finite source comparisons do not stand in for those laws.

```sh
python3 scripts/generate-cjk-dictionary.py --check
python3 scripts/generate-cjk-properties.py --check
bun "$BEND" tests/cjk-dictionary.bend -o build/cjk-dictionary.js
BEND="$BEND" BEND_TUS=8 sh scripts/build-pure.sh tests/cjk-dictionary.bend build/cjk-dictionary
bun "$BEND" tests/cjk-word-break.bend -o build/cjk-word-break.js
BEND="$BEND" BEND_TUS=8 sh scripts/build-pure.sh tests/cjk-word-break.bend build/cjk-word-break
python3 tests/cjk_dictionary_check.py
python3 tests/cjk_word_break_check.py
```

Validation used `/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts`. The boundary oracle requires the existing C compiler, Node N-API headers (`/usr/include/node`) and Node exporting ICU78 symbols. Downloads, compiled artifacts and test fixtures remain under ignored `build/`; the versioned dictionary data is a production asset.

## Sources and licenses

All ICU source references use [`unicode-org/icu`, tag `release-78.3`](https://github.com/unicode-org/icu/tree/release-78.3):

- `icu4c/source/data/brkitr/dictionaries/cjdict.txt`, SHA-256 `e73fd72048981d0cc13e9dc436a7eaba07ffb6eff58c8a59dc75c1df746663a0`.
- `icu4c/source/common/dictbe.cpp`, SHA-256 `7ff35464a40669eb77ef4931f0fe6a041392f12603f07908af309dda3e22a022`.
- `icu4c/source/data/brkitr/rules/word.txt`, SHA-256 `8c623551556473c97f32a1ecc22716c4d73fbf71b8dc500a4b461302ca146171`, documents the pending outer range/status layer.
- `LICENSE`, SHA-256 `e55522d81edc687a341a4411e0776e54ca654e90147f354a90458aaced4116af`.

The adjacent dictionary manifest records the source URL/hash and packed asset hash. `icu78-cjk.LICENSE` retains the complete ICU license and the complete cjdict source notices, including the dictionary's underlying Libtabe/IPADIC notices and its account of removing CC-CEDICT-only words. Generated Unicode property predicates use the existing SHA-pinned UCD17 archive and Unicode License V3.

Root integration at `64fab36`/`f226504` regenerated both assets, rebuilt all fixtures with the shared compiler, and passed all 315,968 prefix and 2,151 segmentation comparisons on Bun/native one/four plus the complete NFKC boundary oracle. Logs: `build/cjk-dictionary-check.log` and `build/cjk-word-break-check.log`.
