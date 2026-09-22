# Native JPEG decoding

`runtime/jpeg.bend` exposes `decode(bytes: List<&2,U32>, limit: Nat) -> Result<&2,&1,Error,Image.Raster>`. It consumes one complete JPEG stream and returns the shared owned RGBA8 raster. `limit` is the maximum pixel count, checked before image-sized allocation; the combined coefficient buffer must also fit the native array index range. This is a pixel budget, not a bound on compressed input or metadata memory.

The implementation supports 8-bit baseline/extended sequential and progressive Huffman DCT, interleaved and separate component scans, DC/AC refinement, restarts, 8/16-bit quantizers, grayscale, RGB/YCbCr and CMYK/YCCK, integer sampling ratios through four, and AVI1/MJPEG default Huffman tables. Reconstruction follows the portable integer IDCT, twofold interpolation and generic nearest-neighbor rules of [jpeg-decoder 0.3.0](https://github.com/image-rs/jpeg-decoder/tree/v0.3.0/src), through the [image 0.24.8 wrapper](https://github.com/image-rs/image/blob/v0.24.8/src/codecs/jpeg/decoder.rs). The pinned executable oracle is Photon **0.3.4**. The inverse-transform source attribution is preserved in `docs/licenses/jpeg-decoder.txt`.

Huffman lossless decoding supports all seven predictors, point transforms and row-aligned restart intervals, with 8-bit gray/RGB/CMYK or 16-bit grayscale. Arithmetic, hierarchical, DNL, noninteger subsampling and unsupported sample precision/color combinations are rejected; unused scaled-DCT and streaming APIs are not provided. EXIF orientation is applied by the image utility, not the codec. Ancillary application data is ignored except JFIF/Adobe/AVI1 flags; this is not an ICC color-management implementation or a validator for ignored metadata syntax.

Header lengths, table references, Huffman code space, scan component identities, progressive coefficient history, entropy bounds/padding and restart order are checked. Truncated entropy is rejected instead of being padded with fabricated values. Duplicate scans, overflowing coefficients, trailing bytes, sequential scans with spectral end zero, and lossless predictor zero are rejected rather than copying the reference's permissive behavior. Predictor zero is reserved for hierarchical differential coding, which the reference and this decoder do not support.

## Correct lossless pixels instead of reproducing corruption

The portable reference predicts from already point-expanded samples and does not reconstruct restart boundaries correctly. Bend keeps prediction in the transformed sample domain and resets the initial/first-row prediction as required by [T.81, H.1.1 and H.1.2.1](https://www.w3.org/Graphics/JPEG/itu-t81.pdf). The user approved preserving correct behavior instead of these reference flaws.

The independent fixture encoder starts from known source samples. For an 8-bit row beginning `20,24,28,32,36` with point transform one, Photon returns `20,44,92,188,124`; Bend restores the original samples. Forty-two fixtures cover all seven predictors, both precisions, point transforms, restarts and their combination. Their expected values come from the source samples, and the harness confirms that Photon differs. They are explicitly separate from exact reference parity. No concrete fixture is presented as a universal proof.

## Reproduction

The pinned Photon package must be available at `build/photon/photon_rs.js`; the existing PNG test harness provides its checksum-verified `--fetch-oracle` download. Pillow is used only to generate independent compressed fixtures, never by production code. The compact independent writer in `jpeg_fixtures.py` covers sampling/color structures and lossless predictions that Pillow does not emit.

```sh
uv venv build/python
uv pip install --python build/python/bin/python Pillow==12.3.0
build/bend-native-toolchain/bend2/main.ts tests/jpeg.bend -o build/jpeg.js
sh scripts/build-pure.sh tests/jpeg.bend build/jpeg
build/python/bin/python tests/jpeg_check.py bun native-1 native-4
```

The suite checks 331 images and 765 exact pixel, budget and malformed-input assertions per backend: 289 images match every pinned Photon pixel, while the 42 corrected lossless cases match independently encoded source pixels. It includes odd and one-pixel dimensions, quality extremes, progressive/refinement/restart combinations, unusual integer sampling ratios, separate scans, Adobe transforms, both quantizer widths, omitted MJPEG tables, 16-bit sample boundaries, larger images and targeted malformed framing/tables/scans.

Complete native runner measurements (three samples, process startup and decimal-byte argument parsing included): 256×256 random JPEG, 18,968 compressed bytes, about 100 ms on one thread / 120 ms on four; 1024×1024 solid JPEG, 17,013 bytes, about 1.11 s / 1.15 s. Both larger outputs matched the pinned reference checksum. These are fixture-specific observations, not an isolated IDCT benchmark or a claim of competitive decoder speed.

## Open compiler defect found during integration

`tests/repro/bool-pick-or.bend` is a positive semantic reproducer. It should print `true`; the installed compiler produces `true` on Bun and `false` on native one/four threads. Generated C packs the generic `Bool.pick(Bool, ...)` result with `term_pak` but directly combines it with an unboxed Boolean OR. The codec expresses that condition with direct comparisons and logical operators; all backend checks remain required. This does not fix the compiler defect.

Observed native toolchain hashes: `bend2/comp.ts` SHA-256 `8a6b8a56960346096e0d881fac2c7aaca8b0c5c337bc12aa292efce3fc54f78f`; `bend2/base.bend` `692d26c4aa2fdcc3b194c5593e5382ec2a31a7abc850ec29882fec600d0e0b26`. Compile the reproducer with the same two commands above, substituting its path and an independent output prefix. Its generated C contains the boxed value fed into raw OR. The compiler owner was notified through the canonical coordination log; no compiler patch or installation was performed for this codec.
