# Native WebP container and default frame

`runtime/webp.bend` provides `decode(bytes, pixelLimit) -> Result<Error, Image.Raster>`. It bounds the RIFF envelope and every chunk before dispatching to the native VP8 or VP8L codec, reconstructs ALPH, and returns the first displayed frame of animated WebP. Production decoding has no host-codec or foreign-library dependency.

The container supports simple VP8/VP8L, extended VP8X, ancillary metadata, raw and lossless-compressed ALPH with all four prediction filters, and ANIM/ANMF first-frame offsets, background and blending. ALPH preprocessing values 0 and 1 have the reference behavior; the hint does not alter decoded bytes. A full-canvas first frame follows the pinned direct-output path. A partial frame uses the VP8X alpha flag to choose transparent or ANIM background, then applies frame blending. Blend arithmetic preserves the pinned binary64 expression order and truncation using native Base F64.

The reference is [image-rs 0.24.8 decoder.rs](https://github.com/image-rs/image/blob/v0.24.8/src/codecs/webp/decoder.rs) and [extended.rs](https://github.com/image-rs/image/blob/v0.24.8/src/codecs/webp/extended.rs), exercised through pinned Photon 0.3.4. VP8 and VP8L details and separate validation are in `tests/vp8.md` and `tests/webp-lossless.md` respectively.

After compiling `tests/webp.bend` to Bun and ordinary-O1 native artifacts, run:

```sh
python3 tests/webp_check.py --runner build/webp.js --photon build/photon/photon_rs.js
python3 tests/webp_check.py --runner build/webp --threads 1 --photon build/photon/photon_rs.js
python3 tests/webp_check.py --runner build/webp --threads 4 --photon build/photon/photon_rs.js
```

All three backends pass 382 exact Photon container/default-frame comparisons, 128 independently specified ALPH filter/implicit-stream checks, eight complete libwebp lossy/alpha file comparisons, two unknown-chunk cases and 53 malformed/budget checks. Container comparisons include all crafted lossless cases and first-frame alpha 0/1/17/127/128/254/255, blending enabled/disabled, both canvas background policies, full/partial frames, offsets and ignored subsequent frames. The lossy oracle decodes YUV with libwebp and performs the pinned RGB conversion independently; it avoids confirmed defects in Photon described by the VP8 test record. Alpha is compared against the original encoder input independently of that RGB oracle. Integration used VP8 commit `a25e867`, source SHA256 `df6628467a45045b62b93721d135703df836be02b41c133c3996f5758c739d94`.

Invalid bytes, RIFF/chunk extents, header/reserved fields, dimensions, missing image payloads, alpha descriptions and frame bounds return typed errors. Canvas and codec allocations honor the caller's pixel budget. A static extended canvas must match its decoded image dimensions. ANIM/ANMF requires the animation flag. Unlike the reference's ignored outer RIFF length, bytes outside the declared RIFF envelope are rejected.

Bounded unknown top-level metadata chunks are skipped, as WebP's extensible container permits. The pinned parser inconsistently ignores only trailing unknown chunks and rejects unknown chunks preceding recognized data. This accepted adaptation does not let unknown chunks replace VP8X, ANIM or the required image payload, nor bypass RIFF bounds. The pinned Pi image-processing/image-process/image-resize-callers suites contain no assertion requiring that inconsistent behavior.

This is the default still-image decode API needed by Pi. It does not expose an animation iterator or a WebP encoder, neither of which is required by that path. Later animation payloads are bounded but not entropy-decoded; only the selected first frame supplies pixels. Codec validation does not by itself mark Pi's broader image or tool suites fully ported.
