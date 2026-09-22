# Native JPEG encoding

`packages/runtime/src/jpeg-encode.bend` implements baseline JFIF JPEG in pure Bend. `encode(image, quality, limit)` returns the owned `Image.Raster` alongside encoded bytes or a typed error, including on a budget failure. The budget counts every byte, including markers and entropy-byte stuffing. Invalid dimensions, insufficient pixel storage, and quality values outside the source's byte domain are rejected before encoding. Dimensions must be positive, at most 65535 on each axis, and satisfy the shared raster's pixel-count bound.

The reference is pinned Photon 0.3.4, using the image-rs 0.24.8 [encoder](https://github.com/image-rs/image/blob/v0.24.8/src/codecs/jpeg/encoder.rs), [transform](https://github.com/image-rs/image/blob/v0.24.8/src/codecs/jpeg/transform.rs), and [entropy coding](https://github.com/image-rs/image/blob/v0.24.8/src/codecs/jpeg/entropy.rs). This software is based in part on the work of the Independent JPEG Group. The translated fixed-point transform's attribution and conditions are retained in [jpeg-ijg.txt](../docs/licenses/jpeg-ijg.txt), together with the original, unmodified libjpeg 9a [README](../docs/licenses/ijg-README) and the [image-rs license](../docs/licenses/image-rs-LICENSE.txt). The Bend translation uses fixed row/block records and explicit unsigned-word two's-complement arithmetic; it does not call a host codec.

The encoder preserves the actual reference's three full-resolution components (4:4:4), not its stale 4:2:2 documentation comment. Alpha is discarded without premultiplication or compositing. Right/bottom block padding repeats the edge pixel. Quality 0..255 is clamped to 1..100 exactly as the reference's byte-typed API; values above 255 return `InvalidQuality` rather than recreating a JavaScript-to-byte wrap. Coefficient quantization preserves the reference's integer truncation before rounding. No generic image metadata or decoder is implemented in this module.

`jpeg_encode_check.py` compares complete output bytes against the pinned Photon WASM encoder, whose result is also decoded by Photon and checked for dimensions. Byte equality includes compressed coefficients, quality tables, framing, stuffing, and final padding, and implies identical decoded pixels. The corpus has 359 cases covering constant/saturated colors, gradients, deterministic random images, every relevant 8×8 edge shape, quality boundaries, alpha independence, and a generated 256×256 image. Another 22 cases check exact-size/one-byte-short/zero budgets and invalid dimensions/pixel capacity/quality. The Bend fixture checks every retained input pixel on all ordinary success/error paths and checks dimensions plus a sentinel pixel for deliberately invalid rasters.

All 381 cases pass the exact same source on Bun and optimized native one/four threads. Tests use Photon only as an external reference; production needs no Photon, JavaScript, or foreign codec. Commands from the repository root:

```sh
build/bend-native-toolchain/bend2/main.ts tests/jpeg-encode.bend -o build/jpeg-encode.js
sh scripts/build-pure.sh tests/jpeg-encode.bend build/jpeg-encode
python3 tests/jpeg_encode_check.py --photon /path/to/photon_rs.js -- bun build/jpeg-encode.js
python3 tests/jpeg_encode_check.py --photon /path/to/photon_rs.js -- env BEND_THREADS=1 build/jpeg-encode
python3 tests/jpeg_encode_check.py --photon /path/to/photon_rs.js -- env BEND_THREADS=4 build/jpeg-encode
```

On this server the focused optimized build took about 3.4 seconds and 190 MiB peak RSS. A single generated 256×256 quality-90 fixture took 0.11 seconds/18 MiB native and 1.36 seconds/172 MiB Bun, including random image generation, retained-raster comparison, and decimal output serialization; these are not isolated encoder benchmarks. Larger decimal-input testing re-encountered the documented Base `String.split` hosted stack limit, so the fixture uses the existing tail-recursive runtime splitter. No compiler patch or reduced image size was used to hide that problem.
