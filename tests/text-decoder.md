# Streaming file text decoding

`runtime/text-decoder.bend` detects UTF-8 and BOM-marked UTF-16LE/BE, strips one leading encoding marker, and emits complete Unicode scalars without retaining the input. `step` and `feed` retain incomplete code units across calls; `finish` rejects unfinished UTF-8, an odd UTF-16 byte, or an unpaired high surrogate. Malformed encodings produce typed errors with source-byte offsets. NUL is a valid scalar: binary-file policy belongs to the caller.

The native port deliberately rejects malformed text instead of replacing invalid encodings. This follows the project's strict-input policy. The decoder does not implement arbitrary legacy encodings or interpret a non-BOM file as UTF-16. The focused runner compares 5,063 whole/split cases against Python's strict codecs, including supplementary scalars, embedded/repeated BOMs, invalid continuations, overlong UTF-8, surrogate errors and final partial sequences. Bun and O1 native one/four workers pass.

```sh
/path/to/bend2/main.ts tests/text-decoder.bend -o build/text-decoder.js
BEND=/path/to/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/text-decoder.bend build/text-decoder
python3 tests/text_decoder_check.py bun native-1 native-4
```

Root integration rebuilt both outputs using `build/bend-process-files/bend2/main.ts`; all 5,063 comparisons pass on Bun and optimized native one/four threads. No new compiler effects were required.

A settled UTF-8 ASCII fast path avoids temporary scalar lists and codec fragments while preserving offsets and BOM state. All 5,063 codec comparisons still pass on Bun/native one/four. `tests/text-decoder-benchmark.bend` isolates 1,048,576 ASCII decoding steps and checks the emitted checksum; seven alternating measured before/after pairs (after one warmup each), O1/native one worker, gave medians 77.43 ms before and 49.03 ms after. The baseline module is unchanged from commit `b9306ca`; both artifacts used the shared compiler. This measures decoder work only, including process startup, and is not an end-to-end grep speed claim.
