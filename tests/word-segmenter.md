# ICU78 outer word rules and lexical dispatch

`runtime/word-segmenter.bend` combines ICU 78.3's exact default word-rule automaton with the native weighted CJK engine. It returns `Segment{text,isWordLike,status}` in source order; status preserves ICU's numeric rule status (0, 100, 200 or 400), and `isWordLike` follows the word-status interval. Mixed Latin, numbers, punctuation, Hebrew, emoji, CJK and Hangul retain their ICU boundaries and lexical classification. Pure UAX default segmentation remains available independently in `word-break.bend`; it is not substituted for ICU's tailored outer rules.

This is a checked default capability, not a claim that every language engine is complete. Multi-character dictionary regions requiring Thai, Lao, Myanmar/Burmese or Khmer engines return `MissingEngine{language}`. Those LSTM/dictionary implementations remain required work. A one-scalar rule region needs no dictionary refinement and follows its rule result, as ICU does. Other scripts that ICU deliberately leaves to its unhandled-script behavior retain the outer rule boundaries. Phrase segmentation is outside this word-navigation interface.

## Explicit immutable context

Load the two production assets once using the existing filesystem interface, decode them with `word-rules.decode` and `cjk-dictionary.decode`, and call `WordSegmenter.create(rules,dictionary)`. The resulting `Context` owns immutable rule tables, the shared weighted dictionary and native normalization tables. `WordSegmenter.segments(context,text)` returns `Result<MissingEngine | InvalidState,List<Segment>>`; the latter error guards internal partition/progress invariants. No host code participates in production segmentation.

For UI navigation, an adapter maps these segments to `Word.Segment{text,isWordLike}`, maps `MissingEngine{language}` to `Word.MissingWordEngine{language}`, and uses `findWordForwardChecked`/`findWordBackwardChecked`. The checked callback has type `Context -> String -> Word.ResultOf(List<Word.Segment>)`; the atomic predicate remains independent. Fully supplied custom segmenters can still use the original infallible navigation APIs. Input and Editor retain ownership of paste-marker overrides and their own component state.

## Exact table and dispatch behavior

The 15,884-byte versioned rule asset contains 58 DFA states, 31 character categories and 2,316 scalar property ranges. The generator checks ICU's compiled rule source against the exact comment/whitespace-stripped pinned `word.txt`. It pins the compiled-rule and full-domain category hashes, validates every transition and status set, and asserts that this word machine has neither hard lookahead nor synthetic beginning-of-input transitions. A future data version requiring those mechanisms cannot silently pass generation. Runtime parsing validates the versioned header, bounds, complete state/category coverage and sorted scalar ranges before constructing balanced immutable lookup tables.

The forward machine retains the most recent accepting boundary and its original suffix, allowing punctuation lookahead without copying or repeatedly reversing entire prefixes. The accepted rule region then drives dictionary dispatch. Contiguous CJK/Hangul engine ranges are refined inside that region; the engine's terminal endpoint is omitted, then the outer rule endpoint is retained. This preserves ICU's attachment of intervening marks and non-dictionary prefixes/suffixes. Every subdivided piece receives the parent rule's final status, matching ICU's dictionary cache. Unsupported required engines fail explicitly instead of yielding a fabricated region.

## Approved deterministic correction

ICU's lazy CJK engine cache exposes a history-dependent bug for Common-script prolonged Katakana marks. In a fresh Node process with ICU 78.3:

```js
const s = new Intl.Segmenter("en", {granularity: "word"});
const text = "ー".repeat(12);
console.log([...s.segment(text)].map(x => x.segment)); // one 12-scalar segment
[...s.segment("日本")];
console.log([...s.segment(text)].map(x => x.segment)); // twelve one-scalar segments
```

`CjkBreakEngine` explicitly handles these Common-script marks, but the language factory cannot initially create it from Script=Common. Once an earlier Japanese/Chinese input has loaded it, the same marks reach that engine. The user approved deterministic segmentation with CJK loaded from the start. Native contexts therefore use the CJK engine immediately and consistently, matching ICU's initialized-engine result. The test oracle explicitly initializes ICU with `日本` before comparison; this is a documented behavior correction, not hidden emulation of cache history.

## Evidence and reproduction

`tests/word_segmenter_check.py` passes 16,446 exact results on Bun and native one/four threads. It compares every segment string, lexical flag and numeric status against Node's ICU 78.3 engine and separately confirms that ICU's strings/flags agree with `Intl.Segmenter`. Coverage includes the 1,944 official Unicode word-boundary inputs (against ICU's actual tailoring), exhaustive triples of 12 mixed word/mark/punctuation/emoji units, both ends of every generated scalar-property range, surrounding Latin/numeric/CJK contexts, 1,024 random mixed-language strings, explicit missing-engine results, and five long inputs including 100,000-letter and 100,000-mark runs. The first case exercises Common marks before any earlier native text can initialize hidden state.

The passing corpus took about 11.962 seconds on Bun and 0.918/1.016 seconds on native one/four threads, including dictionary loading and output. These are observations from a shared machine, not controlled throughput benchmarks. Generic maximal-rule-match, partition/status and dictionary-dispatch laws remain unproved; these differential checks are not presented as proofs.

```sh
python3 scripts/generate-word-rules.py --check
bun "$BEND" tests/word-segmenter.bend -o build/word-segmenter.js
bun "$BEND" tests/word-segmenter.bend -o build/word-segmenter
python3 tests/word_segmenter_check.py
```

Validation used `/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts`. Regeneration uses a test-only N-API extractor built with the existing C compiler and `/usr/include/node` headers. It reads pinned ICU78 data from Node's exported ICU symbols; its runtime oracle also reads ICU break statuses. The extractor/addon never supplies production behavior. Cached source/oracle output stays under ignored `build/`; the production rule asset and manifest are checked in.

## Provenance

Sources use [`unicode-org/icu`, tag `release-78.3`](https://github.com/unicode-org/icu/tree/release-78.3):

- `icu4c/source/data/brkitr/rules/word.txt`: SHA-256 `8c623551556473c97f32a1ecc22716c4d73fbf71b8dc500a4b461302ca146171`.
- `icu4c/source/common/rbbi.cpp`: SHA-256 `2f7f74a05020b59789c2340735452aa3fe535d5b54e21845087bd3a98c832640`.
- `icu4c/source/common/rbbi_cache.cpp`: SHA-256 `2dbb8d13fff4c9763a37573a471a6c994777ad38c1653bb88b4fe253bcf9c35f`.
- `icu4c/source/common/brkeng.cpp`: SHA-256 `1b909e191da0dcad19017aa95c57910b515e0338d92382eb22b9654ef3b4b19a`.

The manifest pins the raw compiled-rule hash, full scalar-category hash and packed production asset hash. Script dispatch uses the existing SHA-pinned Unicode17 UCD archive. The adjacent `icu78-cjk.LICENSE` retains the full ICU license; Unicode property data uses the existing Unicode License V3. The independent UAX module and its conformance contract are unchanged.
