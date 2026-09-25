# Native CLI file arguments

`packages/coding-agent/src/cli/file-processor.bend` ports pinned Pi's `processFileArguments`, `ProcessedFiles`, and `ProcessFileOptions`. The caller supplies the existing `Paths.Environment`; filesystem processing stays sequential, empty files are skipped after stat and before content reads, text strips one leading UTF-8 BOM, and text references and image attachments retain their independent input order. Image MIME sniffing, native processing, resize/convert hints, omission, and the default resize option use the same libraries as the public read tool. References preserve upstream formatting without adding XML escaping.

The previously read-tool-local filename fallback implementation now lives in `Paths.resolvedReadPath`, shared by both callers. This is actual shared policy, not a forwarding wrapper: original spelling wins, then screenshot AM/PM spacing, NFD, curly apostrophes, and combined variants are tried. Existing read callback injection and owned callback lifetime are unchanged. `File.size_bytes` and `FS.size` preserve stat-before-read behavior for empty and procfs files without narrowing large file sizes to a Bend Nat.

The native library returns typed `InvalidPath`, `NotFound`, `Stat`, `Read`, and `InvalidEncoding` errors. It does not print diagnostics or exit the caller; the CLI owns that policy. Native filesystem/UTF-8 error detail is retained. As already approved for malformed input, invalid UTF-8 is rejected instead of Node's replacement-character decoding. Paths use the existing native URL validation, so invalid remote file URLs are rejected. These deliberate API differences do not alter the valid-input assertions below.

`file_processor_check.py` runs the actual pinned source at `46c9de402bddf46b03c3b9f46487b777aaa41861` with Photon 0.3.4. Its image-worker wrapper only substitutes the source's in-process implementation; production remains native Bend. Twelve complete file-list comparisons exercise empty arguments/files, CRLF, one/double/BOM-only text, duplicates, symlinks, zero-size procfs content, home/path fallback variants, mixed PNG/JPEG/GIF/BMP and text, small/oversized images, resizing enabled/disabled/default, conversion hints, and omission. Independent image encoders compare exact MIME/text/order and decoded pixels when compressed bytes differ. Additional assertions cover missing files/directories, strict UTF-8 errors, file URLs, and exact-name precedence.

The named upstream assertion **`image-resize-callers.test.ts` → `file processor omits image attachments when auto-resize cannot produce a safe image`** is exercised with a real malformed GIF recognized by the MIME sniffer: native processing returns the omission text and no image attachment. This covers the actual default processing path, rather than replacing it with the upstream test's mocked resize return.

```sh
build/bend-files/bend2/main.ts tests/file-processor.bend -o build/file-processor.js
BEND="$PWD/build/bend-files/bend2/main.ts" sh scripts/build-pure.sh tests/file-processor.bend build/file-processor
python3 tests/file_processor_check.py --photon /path/to/photon_rs.js bun native-1 native-4
```

The native runner explicitly passes `--threads 1` and `--threads 4`. The public read fixture is also rerun after shared path-policy consolidation; its actual file/path/argument/truncation and injected image-processing cases guard the existing caller.

Validation completed on the exact source with Bun and optimized (`-O1`) native one/four threads: all twelve file-list comparisons and additional assertions passed on each backend. The existing public read suite also passed on all three backends after the policy move.

Since v0.87.1 (f5c946480) the CLI processes `@file` images with `autoResizeImages: false`; AgentSession resizes prompt images once the request model is settled. `tests/file_processor_check.py` ports "can defer resizing file attachments until prompt dispatch": with auto-resize off, a 2010 px PNG that the default would shrink is attached with its original bytes.
