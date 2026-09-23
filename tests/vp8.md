# Native VP8 keyframe decoding

`packages/runtime/src/vp8.bend` decodes a raw WebP `VP8 ` chunk with `decode(payload, pixelLimit) -> Result<&2,&1,Error,Image.Raster>`. It returns opaque packed RGBA; RIFF, extended WebP metadata, alpha, and animation frame composition belong to `webp.bend`. Production code is entirely Bend. No host codec supplies production pixels.

Implemented: boolean arithmetic decoding, all 1/2/4/8 coefficient partitions, adaptive coefficient probabilities, segment maps and absolute/delta quantization, all ten 4×4 intra predictors, 16×16 luma and 8×8 chroma prediction, inverse DCT/Walsh transforms, both loop filters, filter deltas and sharpness, edge padding, and RGB conversion. The decoder retains the pinned pipeline's nearest-neighbor chroma sampling and integer BT.601 conversion. This is distinct from libwebp's optional fancy chroma upsampler, so the independent oracle decodes Y/U/V with libwebp and applies the specified conversion explicitly. Pixel comparisons are against decoded lossy output, never original input pixels.

Dimensions and the pixel budget are checked before reconstruction allocation. Invalid byte values, non-keyframes, unsupported profiles, invisible frames, missing signatures, zero dimensions, partition bounds, reserved color space, and excessive entropy reads return typed errors. A one-byte unused coefficient partition is valid. Arithmetic decoding permits one zero-filled lookahead byte, but rejects further exhaustion and stops reconstruction early. The padded planar reconstruction buffer is reused for RGBA output; the logical raster is cropped only after prediction and filtering.

References: pinned Photon 0.3.4; image-rs 0.24.8 [VP8 decoder](https://github.com/image-rs/image/blob/v0.24.8/src/codecs/webp/vp8.rs), [transform](https://github.com/image-rs/image/blob/v0.24.8/src/codecs/webp/transform.rs), and [filter](https://github.com/image-rs/image/blob/v0.24.8/src/codecs/webp/loop_filter.rs); [RFC 6386](https://www.rfc-editor.org/rfc/rfc6386); libwebp [filter strength calculation](https://github.com/webmproject/libwebp/blob/v1.2.4/src/dec/frame_dec.c) and [arithmetic reader](https://github.com/webmproject/libwebp/blob/v1.2.4/src/utils/bit_reader_utils.c). Attribution/terms are retained in [image-rs-LICENSE.txt](../docs/licenses/image-rs-LICENSE.txt) and [libwebp-COPYING.txt](../docs/licenses/libwebp-COPYING.txt).

## Corrected reference defects

The user's approved policy is to preserve meaningful functionality without recreating obvious legacy flaws. These decoded-pixel deviations are intentional, independently validated, and reported to the parent task:

- With segmentation disabled, image-rs initializes the segment as absolute quantizer zero and ignores the frame quantizer. The retained [solid-red fixture](fixtures/webp/vp8-solid-red.webp) decodes to `(153,107,109)` in pinned Photon, versus correct `(255,0,2)` in libwebp and Bend. The test checks all 64 pixels against both references. Bend uses the frame quantizer.
- Partial-edge chroma prediction in the reference substitutes sentinel pixels for existing padded reconstructed neighbors, and filtering stops at cropped dimensions. Bend reconstructs and filters padded macroblocks before cropping. Fixing the prediction alone removed 163 differing pixels from a 31×27 diagnostic image.
- The reference uses HEV threshold 1 for every keyframe filter level below 40; the specified threshold is 0 below 15. It also omits the intra reference-frame filter delta, clamps before all deltas are applied, and subtracts the subblock adjustment from both outer pixels. Bend uses the specified thresholds, deltas, and symmetric adjustment. Complete outputs match independent libwebp, including explicit simple filtering and nonzero sharpness.
- The reference rejects legal one-byte unused coefficient partitions, and silently zero-pads indefinitely on exhaustion. Bend accepts the legal partition and rejects excessive reads. These policies broaden valid support and reject malformed streams; there is no committed intentionally broken implementation or negative law test.

An early, ignored diagnostic temporarily reproduced the quantizer-zero defect and matched all three initial Photon samples exactly; that code is absent from the committed implementation and tests. The retained regression uses the actual pinned reference directly.

## Validation

`vp8_check.py` uses FFmpeg/libwebp, FFmpeg/libvpx, and `cwebp` only to generate independent compressed fixtures. `vp8_libwebp_reference.py` calls the system libwebp decoder through test-only ctypes; `vp8_reference.cjs` reads the pinned Photon result for the known deviation. The suite checks 119 complete decoded images and 10 malformed/budget cases on Bun and optimized native one/four threads. Generated images cover 1×1 through 129×97, odd/padded dimensions, solid colors, random pixels, gradients, four qualities, encoder methods 0/3/6, every coefficient partition count, segmented/unsegmented frames, both filters, and sharpness 0/4/7. Coverage assertions check that the generated headers actually exercise the partition/filter/segmentation choices.

```sh
build/bend-native-toolchain/bend2/main.ts tests/vp8.bend -o build/vp8.js
sh scripts/build-pure.sh tests/vp8.bend build/vp8
python3 tests/vp8_check.py --cwebp /path/to/cwebp --photon /path/to/photon_rs.js -- bun build/vp8.js
python3 tests/vp8_check.py --cwebp /path/to/cwebp --photon /path/to/photon_rs.js -- build/vp8 --threads 1
python3 tests/vp8_check.py --cwebp /path/to/cwebp --photon /path/to/photon_rs.js -- build/vp8 --threads 4
```

The focused optimized build took 9.93 seconds and 369 MiB peak RSS on this server. These checks establish the codec's exercised decoding behavior; they do not claim all WebP container or animation behavior is complete. Container/lossless/alpha integration is tracked separately.

The original environment-variable commands did not select the native thread count. The retained optimized artifact was rerun with explicit `--threads 1` and `--threads 4`; both passed all 119 pixel comparisons and 10 rejection cases.
