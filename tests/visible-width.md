# Native grapheme and terminal cell widths

`packages/tui/src/utils.bend` now supplies `graphemeWidth(segment) -> Nat` and `visibleWidth(text) -> Nat`, preserving pinned Pi's actual display policy. It consumes `Grapheme.next` from the native Unicode17 segmentation module, rather than approximating a grapheme as one character or treating every emoji-like sequence as wide. This handoff still leaves wrapping, truncation, column slicing, word segmentation and layout pending.

## Behavior and dependencies

The algorithm retains source ordering: tabs, all-spacing-mark clusters, zero-width clusters, exact RGI emoji, leading nonprinting characters, regional-indicator streaming intermediates, East Asian Width, then trailing terminal-spacing marks and visible characters. It preserves Pi's explicit Myanmar/Indic spacing-mark exceptions and Thai/Lao AM treatment. Ambiguous East Asian characters remain narrow, matching the default of pinned `get-east-asian-width@1.6.0`.

Visible width strips complete controls using the native scanner and concatenates visible runs before segmentation. Styling can therefore split a combining cluster or emoji without changing its width. Visible tabs expand to three spaces before segmentation, as upstream does: merely assigning a tab cluster width three was insufficient when a later spacing mark needs the final space as its visible base. The source differential corpus caught and fixed that distinction before handoff.

Printable ASCII has a direct linear path. Other text streams one cluster at a time, without constructing a list of all clusters. There is no process-global width cache; results remain pure and deterministic. The cluster driver has an `@unsafe` annotation because its next shorter string is returned by `Grapheme.next`; each successful step consumes a nonempty cluster.

`runtime/unicode-17-display.bend` is generated from hash-pinned official [Unicode17 UCD data](https://www.unicode.org/Public/17.0.0/ucd/) and [emoji sequence data](https://www.unicode.org/Public/17.0.0/emoji/). Balanced constant decisions classify marks, controls, format characters, default ignorables, East Asian Width and singleton emoji without constructing a property table per input. All 3,953 RGI emoji are represented exactly. Multi-scalar sequences use a hash to select candidates and compare the full string before accepting; collisions cannot imply emoji membership. The Unicode License V3 already lives beside these generated modules.

The production implementation uses no host Unicode/regex/width library. Test-only `get-east-asian-width@1.6.0` is the exact pinned dependency; its widths agree with the generated Unicode data at every one of the 1,114,112 codepoint positions.

## Original assertions and honest suite coverage

The reference enforces SHA-256 pins on `utils.ts` and the four source test files. It executes complete original test bodies from `truncate-to-width.test.ts`, `wrap-ansi.test.ts`, and `regression-regional-indicator-width.test.ts`, plus the two pure tab-width slice/segment consistency cases. Their assertions execute on the actual source; 105 observed `visibleWidth` calls across 27 named tests are replayed against Bend.

This now covers the meaningful width assertions for tabs, Indic conjuncts, ordinary combining marks, Myanmar spacing marks, Thai/Lao AM, CJK/Japanese, isolated regional indicators, full flags and streaming emoji intermediates. Calls measuring actual source-produced wrapped/truncated/sliced output are valid width checks, but **do not port those producing operations**. The regional-indicator test that invokes wrapping and the tab tests that invoke slicing remain partial as complete scenarios. Native normalization was covered by the prior ANSI handoff; width now also matches the normalized text used by those assertions. No original width observation needed an adapted expectation.

Additional validation:

- A digest over all 1,114,112 codepoint property values matches independent JavaScript Unicode-property regexes and the actual East Asian Width dependency. This includes surrogate positions only as property-table inputs, not as valid native text. This check complements the generator's exhaustive property-run reconstruction and explicit boundary cases; it is not a proof based on collision-free hashing.
- 27,533 direct source comparisons cover every RGI emoji and every streaming prefix, exact-membership near misses, property boundaries, mixed Unicode/combining text, and clusters split by ANSI styling.
- Three cases preserve previously approved CSI/incomplete-control corrections instead of reproducing the old scanner's text-swallowing behavior.
- Four long scans cover 200,000 ASCII characters, one base with 100,000 combining marks, 10,000 ZWJ emoji and 10,000 styled text repetitions.

## Reproduction

```sh
python3 scripts/generate-display-unicode.py --check
npm install --prefix build/ansi-reference --ignore-scripts --no-audit --no-fund get-east-asian-width@1.6.0
bun /path/to/bend2/main.ts tests/visible-width.bend -o build/visible-width.js
BEND=/path/to/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/visible-width.bend build/visible-width
python3 tests/visible_width_check.py -- bun build/visible-width.js
python3 tests/visible_width_check.py -- build/visible-width --threads 1
python3 tests/visible_width_check.py -- build/visible-width --threads 4
```

Dependency: grapheme handoff `57f7f7d` (equivalent local cherry-pick `59dc8a1`). Checked `utils.bend` SHA-256: `52af6d0d6c192f45b52d4c4865e7421fda03088c7ee54a02c472f750af5208ef`; generated display module SHA-256: `6ead8de34f3226b622741088a99773c3ef6e2d64f897b4026bb5f3700797397f`. No compiler patches or global toolchain changes were needed.

Final validation: Bun and optimized native explicit one/four threads pass every original observation, full-property digest, 27,533 differential cases, three corrected-control cases and four long scans above.

Root integration independently regenerated the display data and rebuilt the shared-compiler Bun/native artifacts. All three backends pass the full original-observation, property-digest, differential, corrected-control and long-input checks.
