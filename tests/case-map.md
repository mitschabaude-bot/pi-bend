# Unicode default lowercase

`runtime/case-map.bend` exposes `lower(String) -> String` for Unicode scalar strings. It implements Unicode 17 default full lowercase from UnicodeData simple lowercase fields, unconditional SpecialCasing mappings, and the language-independent Final_Sigma rule. It deliberately does not apply locale-specific Turkish, Azeri or Lithuanian tailoring. This is lowercase, not casefold: final sigma remains distinct, sharp s remains sharp s, and dotted capital I expands to `i` plus U+0307.

The installed compiler's `base.bend` defines `String.to_lower` using `Char.to_lower`, which only adjusts ASCII capitals by 32; it cannot supply this contract. Production behavior here is pure Bend. `scripts/generate-case-map.py` reuses the existing SHA-256-pinned Unicode 17 archive loader and emits balanced tables for mapping offsets, Cased and Case_Ignorable. Unicode 17 has exactly one unconditional multi-scalar lowercase expansion, U+0130; generation asserts that fact so a future Unicode upgrade cannot silently omit additional expansions.

The main scan carries whether a cased scalar precedes the current position through zero or more case-ignorable scalars. Sigma looks ahead across case-ignorable scalars to the next significant scalar. Sigma is itself non-ignorable, so these lookahead runs cannot overlap; each scalar is examined at most once by lookahead and once by the main scan. Case_Ignorable takes precedence where both derived properties hold (for example U+0345). Output is accumulated in reverse and reversed once; one-to-many mappings preserve order.

`tests/case_map_check.py` compares 2,204 exact outputs against independently applied pinned UCD rules and ECMAScript `String.toLowerCase` under Node ICU 78.3 / Unicode 17.0. Coverage includes all 1,563 explicitly mapped scalars, combinations around Sigma involving letters, marks, punctuation, format characters, spaces, emoji and letter numbers, and directed expansion/context examples. A rolling checksum checks lowercase output for every valid scalar separately across the complete Unicode domain (not an exact per-scalar output comparison for the identity remainder). Four long cases cover 100,000 combining marks with/without a following cased scalar, repeated Sigma/mark pairs, and 50,000 dotted-I expansions. All pass Bun and native one/four threads. No generic laws are claimed from these finite checks.

```sh
python3 scripts/generate-case-map.py --check
bun "$BEND" tests/case-map.bend -o build/case-map.js
BEND="$BEND" BEND_TUS=8 sh scripts/build-pure.sh tests/case-map.bend build/case-map
python3 tests/case_map_check.py
```

Validation used `/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts`. Tables are covered by the runtime's existing Unicode License V3 file. This dependency unblocks case-insensitive SelectList filtering; it does not implement locale collation or the pending Intl word-segmentation dictionaries/models.

Root integration regenerated the pinned tables and independently rebuilt hosted/native artifacts with the unchanged shared compiler. All three backends pass 2,204 exact comparisons, the scalar-domain digest and all four long cases.
