# Bounded-stack JSON escaping

The 157,500-byte project-context fixture exposed `runtime/json.escaped` retaining one hosted call frame per scalar. An unchanged generated JS artifact with only its diagnostic catch modified showed repeated `json.escaped` frames and `RangeError: Maximum call stack size exceeded`; prompt construction itself had already succeeded. This is our library recursion defect, not a new compiler claim. A reversed accumulator makes escaping tail-recursive, with bounded (at most six-scalar) escape fragments, then reverses once. The public `escaped` and `quote` APIs, UTF16 normalization, and escape selection are unchanged.

The existing differential generator validates 892 quoting and 114 structured JSON cases, including controls, lone surrogates, surrogate pairs, supplementary scalars and nested values. All pass on optimized native one/four workers. Bun passes the explicitly selected scalar-only subset of 774 quoting and 100 structured cases: its hosted `char_new` rejects non-scalar `Chr{55296}` before entering the codec, so historical surrogate compatibility vectors remain native-only. No surrogate expectations were removed from the full corpus. The existing generator now groups its unchanged checks into 30-call functions because the original single 1,006-call IO expression exceeded the hosted backend stack before executing. `tests/json-escaping.bend` independently checks exact large repeated mixed escaping. The real system-prompt check now validates both raw output and JSON serialization of its 157,500-byte context against pinned Pi text.

Before/after native measurements used the same `-O1` compiler, five alternating process pairs per workload and explicit workers; `/usr/bin/time` reports elapsed seconds and peak RSS. `small` quotes a 60-scalar mixed string 20,000 times; `large` quotes the 157,500-scalar context eight times, consuming each result with a tail-recursive length/checksum. Whole-process times on the shared host, at 10ms resolution, are evidence against a material regression rather than a precise speedup claim.

| Workers / workload | Before median | After median | Before peak RSS median | After peak RSS median |
| --- | --- | --- | --- | --- |
| 1 / small | 60ms | 60ms | 1,920KiB | 2,048KiB |
| 1 / large | 80ms | 70ms | 12,544KiB | 12,672KiB |
| 4 / small | 100ms | 80ms | 2,048KiB | 2,048KiB |
| 4 / large | 120ms | 100ms | 15,360KiB | 15,360KiB |

```sh
BEND=/home/agent/code/pi-bend/build/bend-native-toolchain/bend2/main.ts
BEND="$BEND" python3 tests/json_stringify_vectors.py
BEND="$BEND" python3 tests/json_stringify_vectors.py --scalar-only
"$BEND" build/json-stringify-vectors-scalar.bend -o build/json-stringify-vectors-scalar.js
bun build/json-stringify-vectors-scalar.js
build/test-json-stringify --threads 4
"$BEND" tests/json-escaping.bend -o build/json-escaping.js
BEND="$BEND" sh scripts/build-pure.sh tests/json-escaping.bend build/json-escaping
bun build/json-escaping.js
build/json-escaping --threads 1
build/json-escaping --threads 4
/usr/bin/time -f '%e %M' build/json-escaping --threads 1 small
/usr/bin/time -f '%e %M' build/json-escaping --threads 1 large
```

For the unchanged baseline, build the same positive fixture against parent commit `8b18dde` in an isolated checkout; no modified or deliberately broken implementation is needed. Raw local timing samples were recorded under ignored `build/json-escaping-timing.json`.
