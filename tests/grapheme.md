# Unicode 17 extended grapheme segmentation

`runtime/grapheme.bend` implements default extended grapheme clusters from [Unicode 17 UAX29 revision 47](https://www.unicode.org/reports/tr29/tr29-47.html#Grapheme_Cluster_Boundary_Rules). `segments(text)` returns immutable cluster strings; `next(text)` returns `Maybe<&1,String & String>` containing the next cluster and unconsumed suffix, or None for empty input. This is segmentation of native Unicode strings, not cell width, word segmentation, or emulation of malformed UTF-16 strings.

The scanner implements the ordered control/CRLF, Hangul, extending/spacing-mark, prepend, Indic-conjunct, emoji-ZWJ and regional-indicator rules. Its context retains only the previous class, RI parity, emoji suffix state and Indic suffix state. Long runs never require backward searches. `next` reverses only its current cluster and shares the unconsumed suffix; repeated calls do not measure or copy whole suffixes. Both APIs are linear in the number of input scalars for fixed Unicode data, with bounded call stack and constant scanner context. Output storage is proportional to returned text; a cluster itself can be arbitrarily long.

`unicode-17-grapheme.bend` contains generated balanced property decisions, rather than a property-table tree reconstructed for each short terminal input. ASCII is classified directly and Hangul syllables arithmetically. The generator checks compression against the complete Unicode scalar domain. Source data is downloaded only to ignored `build/unicode-17`, pinned by SHA-256 in `scripts/generate-grapheme.py`: GraphemeBreakProperty, DerivedCoreProperties/InCB, emoji-data/Extended_Pictographic and GraphemeBreakTest. Generated data uses the existing Unicode License V3 in `runtime/unicode-LICENSE.txt`; no host segmentation or external production library is involved.

## Executed checks

Bun and optimized native explicit `--threads 1` and `4` each pass all **766 Unicode 17 GraphemeBreakTest cases**, eight explicit boundary cases, and **3,000 generated comparisons against actual Node Unicode 17 Intl.Segmenter**. Every case exercises both `segments` and repeated `next`, comparing the exact ordered strings. The reference refuses a Node Unicode version other than 17.0. Generated cases sample all property-run edges and focus separately on combining marks, joiners, emoji, RI, Indic linkers, Hangul and controls.

Five in-core long-input fixtures avoid command-line size limits: 100,000 combining marks, 20,000 emoji/Extend/ZWJ repetitions, 50,000 regional indicators, 30,000 Indic linker/consonant repetitions and 100,000 ASCII characters. Exact cluster counts, scalar counts and content digests match for both APIs. Total long-fixture wall times in the measured run were 2.918 s Bun, 0.237 s native one thread and 0.288 s native four threads. These are correctness/growth checks on a shared machine, not a universal performance comparison. No machine-stack overflow occurred.

```sh
python3 scripts/generate-grapheme.py --check
sh scripts/build-pure.sh tests/grapheme.bend build/grapheme
build/bend-native-toolchain/bend2/main.ts tests/grapheme.bend -o build/grapheme.js
python3 tests/grapheme_check.py
```

The private worktree used the existing native toolchain through `build/bend-native-toolchain`; no effect, compiler, allocator or global-install changes. TUI width/wrap consumers remain a separate task. A useful future generic law is that concatenating segments reconstructs the input and all returned clusters are nonempty; no proof is claimed in this conformance-tested handoff.
