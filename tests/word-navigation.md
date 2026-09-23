# Word boundaries and injected navigation

The pure runtime `word-break.bend` implements Unicode 17 UAX #29 revision 47 default word boundaries, with both a complete `segments` traversal and incremental `next`. Its pinned Word_Break and Extended_Pictographic data are generated from the existing Unicode archive by `scripts/generate-regex-unicode.py --word-break`. `--check` checks regeneration and reconstructs all scalar classifications from the compressed ranges. The archive SHA-256 is checked by both the source loader and conformance harness.

This is not Pi's default lexical segmenter. ICU 78.3 additionally uses weighted CJK dictionaries and normalization offsets, Thai/Burmese LSTM models, and Lao/Khmer dictionaries. Those remain production dependencies to implement in Bend; no UAX classifier is passed off as an Intl default and no host segmenter supplies production behavior.

`tui/word-navigation.bend` ports upstream `packages/tui/src/word-navigation.ts` at `46c9de402` with an explicitly injected segmenter and atomic predicate sharing one immutable generic context. A `Segment` carries text and `isWordLike`; indices and original-input fields are unnecessary because validated segments partition the sliced text in order. Cursor positions use Unicode scalar coordinates. Out-of-range cursors and incomplete, empty-element or mismatched partitions return typed errors. Atomic segments take precedence over whitespace and punctuation classification.

Approved behavior correction: upstream backward navigation stalls on `אב'` at cursor 3 because a lexical segment ends in ASCII punctuation. The port skips the contiguous trailing punctuation, producing 3 → 2 → 0. The analogous leading-punctuation case for injected lexical segments also advances. All other compared behavior follows the source, including punctuation runs, whitespace skipping and internal punctuation boundaries.

## Evidence

`tests/word_break_check.py` passes 1,944 official Unicode WordBreakTest cases and seven explicit boundary cases through both APIs on Bun and optimized native one/four threads. Six additional long inputs exercise 100,000 combining marks, punctuation lookahead, 50,000 regional indicators, long ZWJ runs and 100,000 letters; counts, scalar totals and rolling content hashes agree. Existing build results were rerun, not inferred from an earlier agent's report.

`tests/word_navigation_check.py` passes 1,262 comparisons through both infallible and checked callback APIs on the same three backends. It hash-checks and extracts the actual upstream navigation implementation into a test-only oracle, supplies ICU-generated sliced-text fixtures, and additionally enumerates three-segment combinations of lexical, punctuation, whitespace, atomic, Hebrew and emoji units. 220 cases explicitly exercise the approved punctuation-progress correction. Four cases check typed input errors; two verify MissingWordEngine propagation in both directions. Checked segmenters return the existing ResultOf type and unavailable engines never become empty segment lists. The source test categories `basic words: hello world`, `dotted: foo.bar`, `colon: foo:bar`, `path: path/to/file`, `CJK mixed`, `whitespace at boundaries`, `punctuation run: foo...bar`, cursor endpoints, and atomic precedence are exercised. This is differential coverage, not a claim that the default-Intl upstream suite is fully ported. Generic progress/bounds/partition-preservation laws are still unproved; these finite tests do not substitute for proofs.

To reproduce, use the installed Bend compiler (the validation run used `/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts`):

```sh
bun "$BEND" tests/word-break.bend -o build/word-break.js
BEND="$BEND" BEND_TUS=8 sh scripts/build-pure.sh tests/word-break.bend build/word-break
bun "$BEND" tests/word-navigation.bend -o build/word-navigation.js
BEND="$BEND" BEND_TUS=8 sh scripts/build-pure.sh tests/word-navigation.bend build/word-navigation
python3 scripts/generate-regex-unicode.py --word-break --check
python3 tests/word_break_check.py
python3 tests/word_navigation_check.py --upstream ../pi-mono
```

The oracle needs Bun and a checkout of the pinned source; its temporary TypeScript and all compiled outputs stay under ignored `build/`.

Root integration regenerated the word property data from the hash-pinned local UCD archive and independently rebuilt both fixtures with the shared compiler. All three backends pass the complete boundary and navigation runners described above.
