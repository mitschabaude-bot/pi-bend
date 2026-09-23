# Terminal images

`packages/tui/src/terminal-image.bend` ports the pinned `terminal-image.ts` module into one cohesive native implementation. Kitty chunking/deletion, iTerm2 encoding, dimensions and sizing, image rendering, cropping, placement-only commands, metadata eviction/generations, fallback file links and capability precedence are implemented. `State` holds the capability cache, programmatic overrides, cell dimensions and the bounded 1,000-image registry; callers retain immutable snapshots. `Environment` supplies terminal variables, platform and home explicitly. `getCapabilitiesWithProbe(state, environment, cwd, processEnvironment)` performs the real tmux probe only when needed, using the shared native runner's stdout-only mode, 250ms deadline and 1MiB stdout limit. Stderr is ignored by the consumer but fully drained, and all readers/timers/callbacks retire before return. Probe failures yield false, matching Pi.

Public names are retained with explicit state/options and typed errors. `ImageDimension` distinguishes cells, pixels, percentages and auto sizing; numeric dimensions use native F64 arithmetic in the same order as source, while pixel dimensions and Kitty IDs are unsigned words and row/column positions are natural numbers. `renderImage` returns `Rendered{state,image}` inside a result; the no-image case returns `None` before validating unused image data. The caller can retain its original state on failure. `allocateImageId` uses the existing OS-backed uniform sampler in the source's actual range 1 through 0xfffffffe; entropy errors remain typed. File links use native POSIX path rules; Windows capability detection is testable through explicit input, but Windows path/OS execution is not claimed.

The original tests are executed against the actual pinned TypeScript module in a test-only sandbox with explicit environment/probe inputs. Ninety-five captured complete results from 72 named cases are compared with Bend, alongside 764 additional protocol/environment/size/header/link comparisons (including every ASCII filename byte), 18 strict-input/header cases and 14 explicit cache/registry transitions plus 32 allocated-ID range checks. [terminal-image-map.json](terminal-image-map.json) records every named test. The three tests requiring the separate `Image` component are covered by [image-component.md](image-component.md); the historical test that recreates the broken old recognizer is deliberately excluded. Captured placement generations are normalized to a fresh registry; replacement, eviction and retained-snapshot generation behavior is checked independently in Bend. No JavaScript supplies production image or capability behavior.

Intentional malformed-input corrections follow the user's reject-invalid policy: base64 must be canonical; zero IDs/counts and zero/nonfinite/negative dimensions reject rather than silently disappear or clamp; invalid crop ranges reject when metadata is present; OSC hyperlink URLs reject control characters. Malformed UTF-8 in tmux stdout rejects the probe rather than replacing bad bytes and potentially accepting a later feature token. Header probes validate framing/signatures and positive dimensions rather than trusting arbitrary offset bytes, without decoding raster pixels or promising full-file/CRC validation. JPEG shares segment/component parsing with the native decoder and recognizes its supported SOF C0–C3, including lossless C3, and preserves valid 12-bit C1/C2 metadata independently of raster-decoder precision support; Pi only recognizes C0–C2. A correctly framed short VP8L dimension header is accepted rather than rejected by Pi's unrelated global 30-byte minimum. Integer crop ratios avoid floating rounding artifacts at sizes beyond binary64 exact-integer arithmetic. Valid positive fractional cell limits retain source floor/minimum-one behavior. None of the original valid-input assertions changes.

```sh
BEND=build/bend-process-files/bend2/main.ts
bun "$BEND" tests/terminal-image.bend -o build/terminal-image.js
BEND="$BEND" sh scripts/build-pure.sh tests/terminal-image.bend build/terminal-image
python3 tests/terminal_image_check.py bun build/terminal-image.js
python3 tests/terminal_image_check.py -- build/terminal-image --threads 1
python3 tests/terminal_image_check.py -- build/terminal-image --threads 4
bun "$BEND" tests/terminal-image-state.bend -o build/terminal-image-state.js
BEND="$BEND" sh scripts/build-pure.sh tests/terminal-image-state.bend build/terminal-image-state
bun build/terminal-image-state.js
build/terminal-image-state --threads 1
build/terminal-image-state --threads 4
BEND="$BEND" sh scripts/build-pure.sh tests/child-execute.bend build/image-child-execute
BEND="$BEND" sh scripts/build-pure.sh tests/child-process.bend build/image-child-process
python3 tests/terminal_image_probe_check.py
python3 tests/child_execute_check.py --prefix build/image-child-execute
python3 tests/child_process_check.py --prefix build/image-child-process
```

The native probe checks cover split stdout, Unicode-trimmed feature tokens, false positives, missing/nonzero/slow tmux, invalid UTF-8, output limits and stderr larger than a pipe buffer. Seven stdout-selection scenarios include 50 repeated executions and sustained post-exit stderr activity. Existing merged-output gates retain 45 execution scenarios, 75 timeout conversions, 29 draining scenarios and 40 same-runtime descriptor checks per native backend. Process execution is currently a Linux-native primitive; hosted pure image/state comparisons are supported, while hosted probing safely falls back on the existing unsupported-process error.

Root integration at `fcf94fe` rebuilt the protocol/state and process fixtures with the shared compiler. All three backends pass the full comparison/state gate, and native one/four pass the real probes plus unchanged merged-process lifecycle checks. Logs: `build/terminal-image-*-check.log`, `build/image-child-execute-check.log`, `build/image-child-process-check.log`. Every oracle/native batch now checks the result count before comparing values.
