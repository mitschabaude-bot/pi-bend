# Terminal input buffering

`packages/tui/src/stdin-buffer.bend` provides immutable terminal input framing. `process` returns the replacement buffer and ordered data/paste events; `flush` returns pending input without invoking callbacks, and `clear`/`destroy` discard it. `pendingTimeout` selects the configured lone-Escape or incomplete-sequence deadline. It supports CSI, SGR and X10 mouse input, SS3, OSC/BEL/ST, DCS, APC, bracketed paste, the WezTerm doubled-Escape case and duplicate printable Kitty events.

Pending payloads are reversed strings. Each character advances a small parser state; completed payloads are reversed once. Paste termination uses a six-character prefix state, without rescanning the accumulated paste. This avoids the reference's repeated prefix slicing and sequence recognition. No host parser or regular expression supplies production behavior.

The original-source runner executes all **59 named upstream tests** with their assertions, records process/flush/clear calls, and replays those calls against the Bend state machine. Together with fragmented and generated protocol inputs, **421 traces** compare emitted events, remaining input and default timeout selection on Bun and O1 native one/four workers. Native checks additionally cover a supplementary Unicode scalar and 50,000-character control-string/paste payloads. These are differential and runtime checks, not universal proofs.

**The upstream suite remains partial.** Replaying a recorded timeout as a flush checks its state transition, not scheduling. Actual owned timers, cancellation races, listener delivery and terminal byte decoding remain to be integrated. The original custom-timeout tests execute on the reference, but their timing assertions are not yet validated against a Bend driver. Raw byte input and the legacy single-high-byte Meta conversion are also outside this text-state API.

Native data events contain complete Unicode scalars, rather than JavaScript surrogate halves. Bracketed-paste markers are recognized at sequence boundaries; marker-like text inside an OSC/DCS/APC payload is retained in that control string, rather than triggering the reference's global substring search. Empty input during an unfinished paste produces no spurious key event. These follow native text semantics and avoid malformed-stream side effects. No interactive editor or terminal parity is claimed by this milestone.

```sh
build/bend-process-files/bend2/main.ts tests/stdin-buffer.bend -o build/stdin-buffer.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/stdin-buffer.bend build/stdin-buffer
python3 tests/stdin_buffer_check.py
```
