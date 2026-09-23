# Native ICU78 Southeast Asian dictionary segmentation

`runtime/sea-word-break.bend` implements Khmer, Lao, Thai and Myanmar dictionary segmentation with one pure algorithm and explicit language configuration. It reuses the native CJK radix record decoder/tree shape, with separate dictionary-prefix semantics and three-word lookahead. `generate-sea-dictionaries.py` checks every serialized word against the hash-pinned sources, derives exact Unicode17 sets, checks the maximum nested candidate count against ICU's capacity of 20, and retains complete ICU licenses/source notices.

| Language | Entries | Radix nodes | Asset bytes | Maximum word length | Maximum nested candidates |
|---|---:|---:|---:|---:|---:|
| Khmer | 81,028 | 99,837 | 967,939 | 19 | 8 |
| Lao | 30,550 | 37,598 | 346,517 | 32 | 6 |
| Thai | 26,383 | 31,515 | 270,119 | 20 | 5 |
| Myanmar | 41,120 | 50,284 | 542,711 | 33 | 8 |

`sea-word-data.decodeKhmer`, `decodeLao`, `decodeThai` and `decodeMyanmar` parse their corresponding checked dictionary assets. `Sea.Context{language,dictionary}` owns a matching immutable tree and language. `Sea.boundaries(context,text)` accepts one contiguous language Script ∩ Line_Break=SA range and returns scalar endpoints including its terminal endpoint. `WordSegmenter` owns range dispatch, removal of engine terminal endpoints and rule-status propagation. Its loaded constructor is `WordSegmenter.create(rules,cjkDictionary,khmerDictionary,laoDictionary,thaiDictionary,myanmarDictionary)`; component callback APIs remain unchanged.

The core preserves longest-first three-word lookahead, including the last viable two-word candidate when no three-word continuation exists; short-root/nonword combining thresholds; exact end/begin character sets; and combining-mark attachment. Prefix counts include the first attempted mismatching scalar and stop at a terminal leaf. Thai additionally preserves the four-or-fewer-scalar fast path and Paiyannoi/Maiyamok suffix conditions, including repeated-suffix exceptions. Other engines use the original less-than-four cutoff. Matcher recursion uses each generated maximum word length; range iteration uses the original scalar count, since accepting a word or scanning an unknown run advances at least one scalar. These are design invariants, not claimed machine-checked proofs.

## Actual reference engine selection

The reference is Node 24.18.0 with ICU78.3/Unicode17 and `icu_small=false`. Its compiled ICU root has an `lstm` resource naming Thai/Myanmar models, but both model resources are absent. `ures_openDirect` for `Thai_graphclust_model4_heavy` and `Burmese_graphclust_model5_heavy`, and `CreateLSTMDataForScript` for both scripts, return `U_MISSING_RESOURCE_ERROR` (2). ICU's `brkeng.cpp` therefore selects `ThaiBreakEngine` and `BurmeseBreakEngine`. Reading upstream `root.txt` alone had incorrectly suggested that LSTM remained a required dependency; direct resource verification corrected that assumption before implementation.

The test addon exposes this resource check, and the lexical oracle asserts `[0,0,2,2,2,2]`: root opens, root.lstm opens, both models fail, both LSTM factories fail. A future reference build containing the models must be handled explicitly. Native production follows the checked dictionary policy, rather than adding unused LSTM behavior. Long Thai/Myanmar combining clusters retain the actual reference boundaries; no fixed-size LSTM vectorizer buffer or unsafe limitation is copied.

## Validation

`tests/sea_word_break_check.py` passes 820,634 exact prefix counts and descending candidate lists across all four languages on Bun/native one/four threads. It covers every dictionary prefix and each full word plus a same-script scalar, 4,096 random unknown runs per language, joiners, supplementary inputs and long runs. Expected values come from an independent source trie. Following the existing CJK harness, each TSV expectation is checked in Bend with one final result, avoiding per-row hosted output effects.

The mixed lexical/status comparison and current count are recorded in [word-segmenter.md](word-segmenter.md). All four data assets pass regeneration, and all compilation uses `/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts` without compiler changes. Generic progress, partition and maximal-candidate laws remain unproved.

```sh
python3 scripts/generate-sea-dictionaries.py --check
bun "$BEND" tests/sea-word-break.bend -o build/sea-word-break.js
bun "$BEND" tests/sea-word-break.bend -o build/sea-word-break
python3 tests/sea_word_break_check.py
bun "$BEND" tests/word-segmenter.bend -o build/word-segmenter.js
bun "$BEND" tests/word-segmenter.bend -o build/word-segmenter
python3 tests/word_segmenter_check.py
```

## Pinned upstream sources

All paths are relative to [`unicode-org/icu`, release-78.3](https://github.com/unicode-org/icu/tree/release-78.3/icu4c/source). Each dictionary manifest also pins the packed asset and Unicode archive hashes.

- `data/brkitr/dictionaries/khmerdict.txt`: SHA-256 `87bee2d17cd5148aa36957eb05409eefc124de8ad519b81b789298ef3e60b5d9`.
- `data/brkitr/dictionaries/laodict.txt`: SHA-256 `3c876934a3fa81031d2333525eafaca6a7c9f842e3b98f18c38880420afb5d36`.
- `data/brkitr/dictionaries/thaidict.txt`: SHA-256 `3166abde40c0f44ab91c28f5ce96d7d1472cb7882e1c0bda0a72f8f69dba4274`.
- `data/brkitr/dictionaries/burmesedict.txt`: SHA-256 `61d8abc3d9102b2f9bf0c9f44db0d7ab89b18172d8cd26832e4c83174bd8673b`.
- `data/brkitr/root.txt`: SHA-256 `4839be9c00ded89ba135c78656257e6eb598f43a0c051aa7a0244183f03c8fd4`.
- `common/dictbe.cpp`: SHA-256 `7ff35464a40669eb77ef4931f0fe6a041392f12603f07908af309dda3e22a022`.
- `common/dictionarydata.cpp`: SHA-256 `cb84f0fff65be65425a6be6b4871cd464862c705d7e7244f91d770b0bd7b1820`.
