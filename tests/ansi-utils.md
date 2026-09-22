# ANSI rendering utilities

`packages/tui/src/utils.bend` implements the ANSI/control and style-state portion of pinned pi-mono `46c9de402`'s `packages/tui/src/utils.ts`. It is one pure module, with no regex or host-language production dependency. Grapheme/cell widths, word segmentation, wrapping, truncation, column slicing and background padding remain pending; this handoff does not claim those upstream suites as ported.

## API and representation

- `extractAnsiCode(text, position: Nat) -> Maybe<AnsiCode{code,length}>` recognizes complete CSI, OSC and APC sequences. Positions and lengths count native Unicode scalars, not UTF-16 units.
- `tokens(text) -> List<Token{text,control}>` groups visible runs and complete controls. Concatenating their text preserves the original string; incomplete controls remain literal text. This API supports the upcoming width/wrap scans without repeatedly slicing strings.
- `stripTerminalSequences`, `normalizeTerminalOutput`, `getActiveBackgroundAnsi` retain the named public responsibilities.
- `AnsiCodeTracker{attributes,foreground,background,hyperlink}` is immutable. `emptyTracker`, `process(state, code)`, `updateTrackerFromText(text, state)`, `reset`, `clear`, `getActiveCodes`, `getActiveBackgroundCode`, `hasActiveCodes`, and `getLineEndReset` replace the upstream private mutable tracker. Attribute flags are a compact set; color parameter text preserves accepted source spelling. `reset` clears SGR state while retaining a hyperlink; `clear` clears everything.
- `ActiveHyperlink` retains parameters, URL and the original typed BEL/ST terminator. Parsing distinguishes unrelated sequences, link closure and link opening. Line-end cleanup closes underline and active links without clearing backgrounds, and continuation output reopens the same link framing.

Scanning uses tail recursion and reversed accumulators. The two `@unsafe` driver recursions consume a nonempty input suffix/token or one complete SGR group on each iteration; the compiler cannot infer that decrease through the separate scanner result. They do not introduce mutable state or unchecked host operations. Malformed/incomplete OSC/APC input is retained as one literal suffix, avoiding repeated full-suffix rescans.

## Intentional corrections

These follow the project's explicit instruction not to reproduce legacy parsing flaws and are tested separately from source-equivalent inputs:

- CSI uses parameter bytes `0x30..0x3f`, then intermediate bytes `0x20..0x2f`, then one final byte `0x40..0x7e`. The source scans arbitrary text until only `m/G/K/H/J`, which can swallow visible text and misses valid cursor/protocol controls. Complete valid CSI is recognized; malformed or incomplete bytes are retained rather than silently discarded.
- Normalization changes Thai/Lao AM vowels and expands tabs only in visible text. OSC hyperlink URLs and titles remain byte-identical. Upstream decomposes those vowels globally and can change a hyperlink target.
- Empty SGR parameters mean zero/reset. Numeric fields are bounded U32; indexed/RGB channels must be in `0..255`. A malformed or incomplete extended color group leaves the whole SGR update unchanged, instead of interpreting its remaining RGB channels as bold/italic/etc. Unknown well-formed SGR attributes remain ignored. The module preserves the source's supported attribute/reset repertoire rather than claiming every terminal extension.
- Native scalar positions replace UTF-16 offsets. The oracle converts offsets and extracted lengths explicitly, without changing the extracted bytes.

## Validation and scope mapping

`tests/ansi_utils_reference.ts` executes the actual source with its pinned test-only `get-east-asian-width@1.6.0` dependency. Its tracker is the actual upstream class, not a rewritten oracle. The differential corpus checks 2,564 supported-input queries and state traces: compound SGR, reset ordering, individual attribute removal, indexed/RGB color boundaries, leading-zero color spelling, background persistence, independent hyperlink/reset state, BEL/ST preservation, and normal extraction/stripping/normalization.

Two actual original test bodies execute with their original assertions: `normalizes Thai and Lao AM vowels only for terminal output` from `truncate-to-width.test.ts` and `keeps tabs inside terminal control sequences byte-identical` from `tab-width.test.ts`. Their seven normalization calls are replayed in Bend. Width assertions within the first source test execute only in the reference; native width behavior is still pending, so this is partial coverage of that named test and of both containing suites.

Another 24 cases assert the deliberate framing, payload-preservation and malformed-style corrections. Five long cases cover 100 KB plain text, normalization, incomplete/complete control strings and 10,000 control/visible-token pairs. A Linux per-argument limit initially prevented the 12,000-token harness case from launching; reducing it to 10,000 preserved the actual long-token check and did not require a production change.

```sh
npm install --prefix build/ansi-reference --ignore-scripts --no-audit --no-fund get-east-asian-width@1.6.0
bun /path/to/bend2/main.ts tests/ansi-utils.bend -o build/ansi-utils.js
BEND=/path/to/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/ansi-utils.bend build/ansi-utils
python3 tests/ansi_utils_check.py -- bun build/ansi-utils.js
python3 tests/ansi_utils_check.py -- build/ansi-utils --threads 1
python3 tests/ansi_utils_check.py -- build/ansi-utils --threads 4
```

Production source SHA-256: `cce67054c279dfbbe42b30de75481959c94111c2589d05fdb5b57a51f9e113bd`. No compiler changes were needed.

Final result: Bun and optimized native explicit one/four threads pass the full source-equivalent corpus, correction cases and long scans. The hosted long-token case passed after fixing only its argument-size harness limit; native runs exercised the complete final harness directly.
