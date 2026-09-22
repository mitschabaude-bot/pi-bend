# Keyboard parsing and matching

`packages/tui/src/keys.bend` ports pinned `packages/tui/src/keys.ts` at pi-mono `46c9de402`. The cohesive pure module implements legacy terminal sequences, Kitty CSI-u and alternate layout fields, modifyOtherKeys, printable decoding, release/repeat detection, and distinct key parsing and binding matching. Terminal IO and protocol negotiation belong to `terminal.bend`.

## Public model

`Context{kittyProtocolActive, windowsTerminalSession}` replaces hidden mutable globals and environment reads. The terminal owner updates this immutable value; Windows-session detection means a truthy `WT_SESSION` with no truthy `SSH_CONNECTION`, `SSH_CLIENT`, or `SSH_TTY`. `defaults()` supplies both false; `setKittyProtocolActive(active, context)` returns updated context.

`KeyId{key: BaseKey, modifiers: Modifiers}` replaces stringly typed identities. `BaseKey` contains named navigation/control keys, `Function{F1{}..F12{}}`, and `Printable{char}`. `Modifiers{shift, alt, ctrl, superKey}` is a set. `plain`, `ctrl`, `shift`, `alt`, `super` and the upstream combination helpers build typed identities; upstream `Key` string constants become constructors. `parseKeyId` validates configuration strings and `formatKeyId` renders canonical modifier order `shift+ctrl+alt+super`; `esc`/`return` normalize to `escape`/`enter`.

- `matchesKey(context, data, key: KeyId) -> Bool`
- `parseKey(context, data) -> Maybe<KeyId>`
- `decodeKittyPrintable(data)` / `decodePrintableKey(data) -> Maybe<String>`
- `isKeyRelease(data)` / `isKeyRepeat(data) -> Bool`

Parsing and matching intentionally remain separate contracts. Raw backspace overlaps Ctrl+h bindings; legacy Alt+b may match a letter binding while parsing as Alt+Left; raw uppercase parses as uppercase, rather than Shift+lowercase; some unmodified modifyOtherKeys control keys parse but do not match their unmodified bindings. CSI home/end aliases and keypad, lock-bit, layout-fallback and Kitty-active handling preserve the source's other intentional asymmetries. Release/repeat detection preserves its substring heuristic and bracketed-paste exclusion; it is not a full protocol parser.

## Native adaptations

No original named test needs an adapted expectation. Additional boundary tests record these deliberate corrections, following the project's reject-malformed-input and no-JavaScript-runtime-emulation policy:

- `+` and `ctrl++` denote the real plus key. Upstream splits the identifier on every plus and accidentally fails to match its own `Key.plus` value. `ctrl+` remains invalid.
- Unknown or repeated modifiers reject instead of silently discarding unknown parts or accepting duplicates. Configuration parsing remains case-insensitive.
- Decimal protocol fields are bounded U32 values; overflow and zero modifier encodings reject instead of wrapping through JavaScript bitwise conversions.
- Protocol codepoints, including alternate fields, must be Unicode scalar values. Surrogates and out-of-range values reject. Valid non-BMP values never alias ASCII through UTF-16 truncation: CSI `65583u` does not parse as `/`, and CSI `65583::99;5u` correctly falls back to Ctrl+c.
- A complete protocol sequence must consume the complete input; a trailing newline does not exploit JavaScript regex `$` matching before the final line terminator.
- Typed identities can represent values outside the configuration grammar. In particular, raw uppercase `A` parses and renders as `A`, while a case-insensitive binding identifier `A` means `a`; no universal parse/render/identifier roundtrip is claimed for arbitrary parsed identities.

## Validation

`tests/keys_reference.ts` loads the actual pinned source and executes the actual original test file with its assertions intact. It records the full named-test path and inputs/results of each tested API call; the Bend fixture replays these calls. Test-only source tables generate additional cases without supplying production behavior.

Each checked backend passes all 250 original assertions across 60 named tests, 59,984 separate parse/match/printable/event differential comparisons, 1,576 identifier and Unicode/malformed-boundary checks, and four 120 KB paste/event scans. The corpus covers both Kitty modes and Windows contexts, all legacy tables, control bytes, locks and unsupported modifier bits, layout alternatives, keypad identities, partial sequences and event variants. These are executed source comparisons and boundary checks, not claims of exhaustive proof.

```sh
bun /path/to/bend2/main.ts tests/keys.bend -o build/keys.js
BEND=/path/to/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/keys.bend build/keys
python3 tests/keys_check.py -- bun build/keys.js
python3 tests/keys_check.py -- build/keys --threads 1
python3 tests/keys_check.py -- build/keys --threads 4
```

The checked native artifact uses the installed compiler/effects copied into the private lock toolchain, normal `-O1`, and explicit thread arguments. Production source SHA-256: `44e3115d045968f593e9783e89aa223c47af8b71534f7d62414755b5f4977293`. No compiler changes, runtime dependency additions, or host-language production adapters were needed.

Root integration rebuilt the unchanged source using `build/bend-process-files/bend2/main.ts`; all original, differential, boundary and long-input checks pass on Bun/native one/four. The pinned keys.test.ts inventory entry is ported; terminal ownership, keybinding configuration and editor integration are separate components.
