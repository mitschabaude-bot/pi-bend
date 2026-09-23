# Native ICU78 Khmer word segmentation

`runtime/khmer-word-break.bend` implements ICU78's Khmer dictionary engine in pure Bend. The pinned `icu78-khmer.bin` contains all 81,028 dictionary entries as 99,837 immutable radix nodes in 967,939 bytes. The engine reuses the existing CJK radix record decoder and tree shape, while supplying its own exact prefix semantics and word selection. The asset generator reconstructs and compares every serialized word, pins the dictionary and Unicode archive hashes, and retains the complete ICU license and Khmer source notices.

`khmer-word-data.decode(bytes)` returns the checked dictionary tree. `Khmer.boundaries(dictionary,text)` accepts one contiguous Khmer Script ∩ Line_Break=SA engine range and returns scalar endpoints including its terminal endpoint. The outer `WordSegmenter` owns range dispatch, removal of engine terminal endpoints, rule-status propagation and attachment of adjacent non-engine text. The loaded context constructor is now `WordSegmenter.create(rules,cjkDictionary,khmerDictionary)`; callers supply all three immutable assets. Component callback APIs remain unchanged.

The core preserves ICU's longest-first three-word lookahead, including selection of the last viable two-word candidate when no three-word continuation exists; short-root/nonword combining thresholds; resynchronization only across permitted end/begin characters; and combining-mark attachment. As in ICU, the prefix count includes the first attempted mismatching scalar and stops at a terminal leaf. The checked source dictionary's maximum word length is 19, so it cannot exceed ICU's 20 candidate limit. Matcher recursion uses this generated bound, and range iteration uses the original scalar count: each iteration either accepts a nonempty dictionary word or consumes at least one unknown scalar before resynchronizing. These are design invariants, not claimed machine-checked proofs.

The public language selection in ICU78 tries LSTM first, but its pinned root resource supplies LSTM models only for Thai and Myanmar. Khmer therefore uses this dictionary algorithm; the remaining Lao dictionary engine and Thai/Myanmar LSTM engines still return explicit missing-engine results in native default segmentation. No host-language code provides production boundaries or dictionary queries.

## Validation

`tests/khmer_word_break_check.py` compares 369,418 exact prefix counts and descending candidate-length lists with an independent source-dictionary trie, covering every dictionary prefix, every word with an appended Khmer scalar, 4,096 random unknown inputs, joiners, supplementary scalars and a 100,000-scalar run. Bun/native one/four threads pass in 23.552/1.844/2.091 seconds. Following the established CJK prefix harness, it uses TSV expectations checked in Bend and a single final result; the initial per-row hosted output harness exceeded 120 seconds, without indicating an algorithm mismatch.

`tests/word_segmenter_check.py` passes 102,087 exact segment strings, word-like flags and numeric statuses on Bun/native one/four threads. The expanded corpus includes every dictionary word, concatenations, random unknown strings, mixed scripts, joiners and long mark runs. Its C status oracle uses UTF-16 UText to match `Intl.Segmenter`: ICU's Khmer minimum checks four native units, which yields different short-run behavior with UTF-8 UText. Every oracle string/flag result is independently asserted against Intl. This corrects the test transport and does not change the native target behavior.

Both data generators pass regeneration checks. All runs use the shared compiler `/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts`; no compiler changes were made. Generic progress, partition and maximal-candidate laws remain unproved.

```sh
python3 scripts/generate-khmer-dictionary.py --check
bun "$BEND" tests/khmer-word-break.bend -o build/khmer-word-break.js
bun "$BEND" tests/khmer-word-break.bend -o build/khmer-word-break
python3 tests/khmer_word_break_check.py
bun "$BEND" tests/word-segmenter.bend -o build/word-segmenter.js
bun "$BEND" tests/word-segmenter.bend -o build/word-segmenter
python3 tests/word_segmenter_check.py
```

## Pinned upstream sources

All paths below are relative to [`unicode-org/icu`, release-78.3](https://github.com/unicode-org/icu/tree/release-78.3/icu4c/source).

- `data/brkitr/dictionaries/khmerdict.txt`: SHA-256 `87bee2d17cd5148aa36957eb05409eefc124de8ad519b81b789298ef3e60b5d9`.
- `data/brkitr/root.txt`: SHA-256 `4839be9c00ded89ba135c78656257e6eb598f43a0c051aa7a0244183f03c8fd4`.
- `common/dictbe.cpp`: SHA-256 `7ff35464a40669eb77ef4931f0fe6a041392f12603f07908af309dda3e22a022`.
- `common/dictionarydata.cpp`: SHA-256 `cb84f0fff65be65425a6be6b4871cd464862c705d7e7244f91d770b0bd7b1820`.
