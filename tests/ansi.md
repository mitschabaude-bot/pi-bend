# ANSI stripping

`packages/coding-agent/src/utils/ansi.bend` ports `stripAnsi(String) -> String` from pinned pi-mono `46c9de402`, `packages/coding-agent/src/utils/ansi.ts`. It is one pure scalar scanner; no regular-expression engine, host callback or terminal dependency supplies production behavior.

The scanner recognizes ESC-prefixed OSC strings terminated by BEL, ESC-backslash or C1 ST; ESC-`[` and C1 CSI controls with parameter bytes 0x30–0x3F, intermediate bytes 0x20–0x2F and final bytes 0x40–0x7E; ESC intermediate/designation sequences; and Pi’s single-ESC final set, including RIS and the explicit g–m / r–t regressions. Standalone C1 OSC, DCS/APC strings and unrelated literal controls are not newly interpreted. Incomplete sequences remain literal. Both output and pending control bytes use reversed scalar lists; each input scalar is visited a bounded number of times, giving O(n) time and O(n) storage, including unfinished OSC strings. No fuel bound or unsafe recursion is needed.

Validation directly imports the pinned upstream function as a test-only oracle: 900 matching cases cover plain/Unicode text, single-ESC controls, CSI semicolon/colon parameters, all three OSC terminators, OSC payloads containing newlines or embedded ESC, and seeded mixtures. Another 84 explicit cases cover deliberate differences and literal preservation. Four in-core 200 KB cases cover plain identity, unfinished OSC identity, completed OSC removal and long CSI parameter removal without fixture argument limits. All pass Bun and ordinary optimized native builds with explicit one/four workers. These are executed checks, not claimed proofs.

The meaningful assertions in upstream `ansi-utils.test.ts` for RIS, single-ESC g–m/r–t and common colored/hyperlinked output are covered. Its generated compatibility test also encodes malformed regex behavior, so the entire upstream suite is not claimed identical. Non-string TypeErrors become a static `String` parameter. Deliberate parsing differences approved for this port are:

- Unterminated OSC and CSI are preserved in full; the regex deletes arbitrary prefixes (`ESC ] unterminated` loses `ESC ] u`, and `ESC [ 123` can disappear).
- Complete CSI accepts standard byte classes and arbitrary parameter length. The legacy four-digit limit and omitted legal final/intermediate bytes do not leak escape fragments.
- Charset designation consumes exactly its sequence. `x ESC ( 0 y` and `x ESC # 8 y` become `xy`; the regex can consume the visible `y` as a final byte. Valid designators such as `ESC * 0` are also recognized.

```sh
build/bend-native-toolchain/bend2/main.ts tests/ansi.bend -o build/ansi.js
sh scripts/build-pure.sh tests/ansi.bend build/ansi
python3 tests/ansi_check.py --runner build/ansi.js
python3 tests/ansi_check.py --runner build/ansi --threads 1
python3 tests/ansi_check.py --runner build/ansi --threads 4
```
