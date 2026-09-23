# Native WebP lossless decoding

`packages/runtime/src/webp-lossless.bend` implements VP8L entropy decoding and all four inverse transforms. `decode` accepts a bounded VP8L chunk payload and an explicit pixel budget, returning owned RGBA8 pixels. `decodeImplicit` accepts dimensions plus the headerless stream carried by compressed ALPH and returns packed ARGB pixels; the container consumes its green channel. Production code is pure Bend.

The codec covers simple/complex canonical Huffman trees and repeat-coded code lengths, spatial entropy groups, color caches, overlapping LZ77 copies and all 120 spatial distance codes, predictor modes 0–13, signed cross-color transforms, subtract-green, and packed delta-coded palettes. A sparse immutable group table retains only groups referenced by the entropy image. Pixel arrays and image traversal use bounded indexes; image dimensions and the caller's pixel budget are checked before image allocation. Working dimensions are retained for each transform and inverses run in reverse order.

The primary reference is [image-rs 0.24.8 lossless.rs](https://github.com/image-rs/image/blob/v0.24.8/src/codecs/webp/lossless.rs), its [inverse transforms](https://github.com/image-rs/image/blob/v0.24.8/src/codecs/webp/lossless_transform.rs) and [Huffman reader](https://github.com/image-rs/image/blob/v0.24.8/src/codecs/webp/huffman.rs), exercised through Pi's pinned Photon 0.3.4 WASM decoder. The implementation is an independent functional implementation of the format, not a runtime binding to that reference. Test-only libwebp encoding supplies additional independently generated streams and expected original pixels.

Run after building `tests/webp-lossless.bend` to Bun and native executables:

```sh
python3 tests/webp_lossless_check.py --runner build/webp-lossless.js --photon build/photon/photon_rs.js
python3 tests/webp_lossless_check.py --runner build/webp-lossless --threads 1 --photon build/photon/photon_rs.js
python3 tests/webp_lossless_check.py --runner build/webp-lossless --threads 4 --photon build/photon/photon_rs.js
```

All three backends pass 328 exact Photon pixel comparisons and 38 malformed/budget checks. Constructed streams cover every predictor, signed transform coefficients, palette packing boundaries, complex Huffman code lengths and repeats, cache widths 1–11, all 120 plane distances and 40 linear distances, overlapping copies through length 4096, spatial groups including unused groups, and combined transforms. Real libwebp samples include a noisy 128×128 image and a 513×255 gradient. Where independently specified, original or constructed expected pixels must also agree with Photon. Large rasters use a full-image digest only for transporting results; every decoded pixel participates.

Malformed byte values, invalid version, invalid Huffman descriptions, illegal cache widths, references outside decoded history or image bounds, duplicate transforms, and used predictor modes above 13 fail with typed errors. Unused palette entries remain transparent zero as specified by the format. The parser stops after the declared number of pixels; trailing entropy padding is not treated as another image. Bounds/error tests are ordinary decoder tests, not compiler mutations or negative law tests.

This validates the lossless codec, not complete WebP container/animation behavior or the full upstream image suite. Container bounds, ALPH filtering, lossy VP8 and default-frame composition are separate integration work. No claim of a general correctness proof is made from these finite comparisons.
