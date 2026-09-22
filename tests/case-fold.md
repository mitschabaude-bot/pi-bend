# Unicode scalar case equivalence

`runtime/case-fold.bend` exports `equal(Char,Char)` and `variants(Char)`. Variants contain the input first and every other member of its default Unicode simple-fold class exactly once. A matcher can test those variants against its original class/range endpoints, then negate the combined membership result for a negated class. Folding only the endpoints of a range is incorrect. The module has no glob dependency, normalization, locale selection, multi-character expansion or runtime foreign calls.

The source is Unicode 17.0.0 [CaseFolding.txt](https://www.unicode.org/Public/17.0.0/ucd/CaseFolding.txt), statuses C and S as specified by that file. Unlisted scalars remain themselves; full and Turkic mappings are excluded. `scripts/generate-case-fold.py` downloads into ignored build cache, verifies SHA256 `ff8d8fefbf123574205085d6714c36149eb946d717a0c585c27f0f4ef58c4183`, and regenerates only the marked data block. Existing `packages/runtime/src/unicode-LICENSE.txt` applies. Regeneration is byte-for-byte stable.

The 2,994 participating scalars form cycles of at most four members. Their next-member mappings compress into 320 contiguous ranges with alternating offsets, searched through the existing immutable U32 table. The generator verifies exact expansion of every compressed range and the cycle bound. This gives bounded lookup and short lists without generated forwarding functions or scanning the whole mapping table per character.

```sh
python3 scripts/generate-case-fold.py
BEND_TUS=8 sh scripts/build-pure.sh tests/case-fold.bend build/case-fold
build/bend-native-toolchain/bend2/main.ts tests/case-fold.bend -o build/case-fold.js
python3 tests/case_fold_check.py
# Optional pinned JavaScript dependency comparison:
python3 tests/case_fold_check.py native-1 --reference /path/to/unpacked/ignore-7.0.8/package
```

Tests check every 1,112,064 valid Unicode scalar, exact membership of every nontrivial class against the official source, singleton identity, no duplicates, both equality directions for every class member, 15 targeted positive/negative literal comparisons and 196 range-membership cases. These are exhaustive finite-data checks and executed regressions, not Bend proofs. All pass on Bun and optimized native one/four workers. Observed full scalar scans, including reporting and equality checks, take 15.0 s hosted and 0.12–0.14 s native; an earlier native variant-only scan used 2.3 MB maximum RSS. These measurements describe this fixture, not complete ignore-matcher throughput.

Pinned `ignore@7.0.8` constructs legacy `RegExp(...,"i")`, without Unicode mode. Comparing all 1,512 official mapping pairs gives 1,161 agreements and 351 intentional differences on Bun 1.4.0: 44 BMP pairs and 307 supplementary pairs. Examples include `ſ`/`s`, `K`/`k`, `ẞ`/`ß`, `Ω`/`ω`, Greek letters with prosgegrammeni, and Deseret capitals/lowercase. These differences follow the requested scalar simple-fold semantics instead of recreating legacy uppercase/UTF-16 matching limitations. Current JavaScript `/iu` agrees with all 1,512 mappings. Dotted/dotless Turkish I remains distinct from ordinary I/i by default, and sharp S does not expand to two `s` characters.

`isUppercase(Char)` additionally implements Unicode 17's derived `Uppercase` property for native glob smart case. Its 2,006 members compress into 158 arithmetic ranges using the same immutable lookup table; this includes `Other_Uppercase` characters outside the `Lu` general category. `generate-case-fold.py` reads official `DerivedCoreProperties.txt` with SHA-256 `24c7fed1195c482faaefd5c1e7eb821c5ee1fb6de07ecdbaa64b56a99da22c08`, verifies exact range expansion, and regenerates both tables. The fixture checks this property on every Unicode scalar as well as the unchanged folding/equality checks. Combined scans measured 28.05 s on Bun and 0.34–0.41 s on native one/four workers; these include both exhaustive scans and output parsing, not just lookup time.
