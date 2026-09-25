# Native read tool

`core/tools/read.bend` now exposes local `ReadOperations`, injectable access/read/optional MIME callbacks, and the public `createReadTool` AgentTool factory. Local operations use `File.access(R_OK)`, full raw-byte reads and the single-read 4,100-byte MIME inspector. Path resolution preserves the original-path, macOS AM/PM spacing, NFD, curly-apostrophe and combined fallback order. Existing pure text selection/truncation remains shared.

The factory owns its execution callback and any default operations it creates. Injected operation and image-processing callbacks are borrowed; the caller disposes them after invocations finish. `disposeTool` does not dispose borrowed callbacks. `invokeWithContext` accepts the extension boundary's cwd override and optional model image capability. The canonical AgentTool execution input has no ExtensionContext, so the AgentTool wrapper supplies an absent context. Extension ToolDefinition/renderers and prompt-contribution registration remain separate integration work.

Image processing is an explicit typed callback receiving the exact bytes, detected MIME and auto-resize flag. It can return processed base64 data/MIME/hints, a supported non-throwing failure message, or a typed operational failure. The read result preserves the upstream text/image ordering, conversion/resizing hints and non-vision note. A non-vision model does not remove the image from the tool result; later request construction owns that policy. The default processor now connects native PNG/GIF/BMP/JPEG/WebP decoding, resizing and PNG/JPEG encoding. It preserves supported input bytes when auto-resize is disabled and converts BMP to PNG. Malformed images produce the upstream non-throwing omission message. Background CPU scheduling remains pending, so this does not claim the complete default image path.

Native adaptations match the existing project policy: offset/limit are exactly representable nonnegative natural counts (negative, fractional, nonnumeric and oversized values fail); invalid UTF-8 text fails instead of silently replacing malformed bytes; filesystem and callback errors are typed, retaining OS causes rather than emulating JavaScript exception objects. Zero offset still means the first line, and zero limit remains valid. UTF-8 BOMs are preserved. Cancellation returns `Aborted` only after in-flight callbacks settle, with cancellation taking precedence over their eventual result; no file operation is detached from its callback owner. The earlier shell-quoting improvement for long-line advice remains in place.

Focused fixtures:

```sh
sh scripts/build-pure.sh tests/read-public.bend build/read-public
sh scripts/build-pure.sh tests/read-operations.bend build/read-operations
build/bend-native-toolchain/bend2/main.ts tests/read-public.bend -o build/read-public.js
build/bend-native-toolchain/bend2/main.ts tests/read-operations.bend -o build/read-operations.js
python3 tests/read_public_check.py
python3 tests/read_operations_check.py
```

`read_public_check.py` calls the actual AgentTool, checks local files/path variants/invalid inputs/truncation and every injected image-processing outcome, and compares text/image execution results with the unmodified execute body extracted from pinned `read.ts`. Only its test image processor and schema/renderer boundaries are supplied by the oracle harness. `read_operations_check.py` checks access→MIME→read→processor ordering, omitted/empty MIME, every operation failure, pre-abort and in-flight cancellation, dynamic cwd/model context, borrowed callback survival, and a channel-gated read that has settled before cancellation returns. Existing `read_text_check.py` independently compares 450 cases with the pinned text implementation; all three backends pass.

The final exact public/operations fixtures are also tested with isolated `PI_BEND_OPT=-O0` native builds on one and four threads; this is a correctness check, not a change to the project's default `-O1` or a performance claim. Earlier `-O1` snapshot results are recorded separately in the coordination log. No upstream tools/image suite is marked fully ported by this milestone.

`image_process_check.py --photon PATH` also exercises the public read factory against real PNG/GIF/BMP/JPEG/WebP files, including the upstream XMP-before-EXIF orientation case and animated WebP first-frame processing, resized dimension notes, disabled resizing and malformed-image omission, with the underlying processing results compared to pinned Pi source. The original three assertions in `image-process.test.ts` are covered; broader image/renderer/caller suites remain partial.

## Image resize profile (v0.87.1, f5c946480)

The image processor receives a resize profile besides the auto-resize flag: the execution context model's `inputLimits.images.resize` (`toolContext` reads it from the session's `ContextView`), or else the tool's own `ReadToolOptions.resizeOptions`, or else none (the conservative 2000 px / 4.5 MiB defaults). `Images.modelResizeOptions` converts the model's numbers; a value that is not a whole number counts as absent, where upstream would hand it to the resizer as is. `tests/read_public_check.py` ports image-resize-callers.test.ts "passes the current model resize profile to the read tool": the pinned `createReadToolDefinition`, executed with upstream's test model as `ctx.model`, and the native tool report the profile their image processors receive (upstream's test observes `resizeImage`'s arguments; both processors here are the injected stand-in), including the fallback profile and the context model winning over it.
