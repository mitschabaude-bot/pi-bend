# ANSI text layout

`packages/tui/src/utils.bend` now implements `wrapTextWithAnsi`, `truncateToWidth`, `sliceByColumn`, `sliceWithWidth` and `extractSegments` from pinned Pi commit `46c9de402`. Widths and columns are natural numbers; `ellipsis`, `pad` and `strict` are explicit arguments. Slice results use `WidthResult{text,width}` and overlay results use `Segments{before,beforeWidth,after,afterWidth}`. There is no shared mutable tracker or locale-dependent production dependency.

Wrapping follows the source's actual rule: literal spaces form space tokens, CJK Script_Extensions graphemes form separate break tokens, and other graphemes form word tokens. It does not call the exported Intl word segmenter. The display generator now includes the exact Han/Hiragana/Katakana/Hangul/Bopomofo Script_Extensions union from pinned Unicode 17 `Scripts.txt` and `ScriptExtensions.txt`; overrides replace the default Script property as required. A full-domain comparison against the pinned source's JavaScript Unicode property regex checks the classification digest independently.

Styles, underline resets, background continuation, OSC 8 hyperlinks and their BEL/ST terminators carry across physical and generated line breaks according to the source. Truncation preserves a contiguous prefix, closes an active hyperlink before its reset/ellipsis, and never resumes after a wide grapheme fails to fit. Slicing preserves complete graphemes and source style inheritance. A forward cursor bounds truncation and slicing work to the needed input prefix instead of allocating a complete list of graphemes from an arbitrarily long suffix; accumulator strings avoid repeatedly copying completed lines. Cursor recursion consumes a complete control or at least one Unicode scalar per step; its progress crosses helper calls, hence the explicit `@unsafe` termination annotations.

The approved control scanner corrections from `ansi-utils.md` still apply: complete CSI grammar, literal retention of malformed/incomplete controls, and preservation of control payloads during normalization. Negative, fractional and non-finite widths cannot be represented by the native `Nat` API. Like upstream, wrapping a glyph wider than the available width preserves the whole glyph (and can emit an empty preceding line), including width zero; truncation and strict slicing instead exclude glyphs that do not fit. This is not a promise that every wrap fits an impossibly narrow column. The implementation preserves the source's grapheme segmentation boundaries at ANSI controls; it does not silently merge across them for slicing.

## Source assertions

`ansi_layout_reference.ts` hash-checks and executes the actual source and test bodies, keeping their original assertions and named-test paths. It captures each layout function's input and complete result, then `ansi_layout_check.py` compares the Bend result exactly. Existing width/normalization assertions in those bodies remain covered by `visible-width.md` and `ansi-utils.md`; executing them in the reference alone is not claimed as new Bend coverage.

| Original suite | Native assertion mapping |
| --- | --- |
| `truncate-to-width.test.ts` | All nine `truncateToWidth` cases: very large Unicode, kept styles, BEL hyperlink closure, malformed prefix termination, clipped wide ellipsis, already-fitting text, padding, empty ellipsis and contiguous prefix. The seven width/normalization cases belong to the earlier milestones. |
| `wrap-ansi.test.ts` | All 16 wrapping cases: three underline, two background, seven basic wrapping and four OSC 8 cases. Three additional basic cases test only width and were ported earlier. |
| `regression-regional-indicator-width.test.ts` | `wraps intermediate partial-flag list line before overflow`; the other four width cases were ported earlier. |
| `tab-width.test.ts` | `keeps slice helper widths consistent with visible width` and `keeps overlay segment widths consistent with visible width`. Input/editor/TUI component cases remain pending. |
| `regression-overlay-cjk-boundary.test.ts` | `excludes a wide grapheme from before when overlay starts inside it` and `keeps ASCII before-segment behavior at the same boundary`. The two compositor cases remain pending with `compositeTuiLine`. |

The corpus supplements these with styled Unicode, tabs, combining marks, CJK, emoji, zero-width controls, strict/non-strict slice boundaries, empty and narrow widths, wide/styled ellipses and long scans. The Unicode property digest is an exhaustive-input regression check, not a collision-free proof. Test-host JSON/reference code supplies no production behavior.

## Reproduction

```sh
python3 scripts/generate-display-unicode.py --check
bun /home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts tests/ansi-layout.bend -o build/ansi-layout.js
BEND=/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/ansi-layout.bend build/ansi-layout
python3 tests/ansi_layout_check.py -- bun build/ansi-layout.js
python3 tests/ansi_layout_check.py -- build/ansi-layout --threads 1
python3 tests/ansi_layout_check.py -- build/ansi-layout --threads 4
```

The reference uses the existing test-only `build/ansi-reference/node_modules/get-east-asian-width/index.js` at version 1.6.0 (setup in `visible-width.md`). No host codecs, locale APIs or regex engine are production dependencies. Word segmentation for editor motions, hit-testing helpers and TUI compositing remain outside this milestone. `applyBackgroundToLine(line,width,bg)` now pads to the requested width before calling the borrowed native `Callback<String,String>` handle; its callback/component assertions belong to the Text/TruncatedText fixture rather than these pure layout comparisons.

Validation completed on Bun and optimized native with explicit `--threads 1` and `--threads 4`: 34 exact layout results across 30 original named tests, 7,640 differential cases, the full-domain CJK classification digest, three long scans and five explicit control-grammar corrections. Existing display/RGI flag values also remain unchanged across all 1,114,112 codepoint positions. Native logs are retained as `build/ansi-layout-{1,4}.log`; the hosted artifact is `build/ansi-layout-stream.js`.

A bounded development comparison of truncating 200,000 emoji/CJK graphemes to 40 columns measured the complete hosted fixture (including startup and input construction): three-run medians were 3.10 s / 365,316 KiB with an eager grapheme list, versus 0.22 s / 129,492 KiB with the final cursor. This compares two implementations of this module, not Bend against upstream TypeScript, and is not a universal performance claim.

Root integration regenerated the Unicode display data and independently rebuilt hosted/native artifacts with the unchanged shared compiler. All three backends pass the complete original-result, differential, full-domain classification, long-scan and approved-correction checks described above.

The readability follow-up names group-boundary predicates and wrap-state transitions explicitly. It also fixes eager group flushing and makes whitespace/CJK scans use tail continuations; the added 100K unbroken-word and 20K combining-mark wrap cases protect the confirmed library performance/stack defects recorded in `docs/bend-issues.md`. The differential corpus and public results are unchanged.

Final follow-up validation passes on Bun and optimized native one/four threads: the unchanged 34 named-test results, 7,640 comparisons and Unicode/control checks, plus all five long cases. Native logs are `build/ansi-layout-clean-{1,4}.log`; hosted checks used `build/ansi-layout-final.js` (the combining-grapheme case was additionally run directly against the source oracle). No compiler or toolchain changes were made.

Root integration independently rebuilt the readability/short-circuit follow-up and passed the full five-long-case runner on Bun/native one/four. The separately compiled TUI compositor also passes its original-result and 609-case reference corpus against this integrated layout implementation.
