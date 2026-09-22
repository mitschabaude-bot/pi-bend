# Streaming output accumulator

`packages/coding-agent/src/core/tools/output-accumulator.bend` ports pinned Pi's `core/tools/output-accumulator.ts` into one module. The accumulator owns an immutable decoding/counting state and either buffered raw chunks or one affine spill-file handle. `create(options)` is pure; `append(bytes, accumulator)`, `finish(accumulator)` and `closeTempFile(accumulator)` return `IO(Outcome<Unit>)`. `snapshot(persistIfTruncated, accumulator)` returns `IO(Outcome<OutputSnapshot>)`. Every outcome returns accumulator ownership alongside its typed result. `getLastLineBytes(accumulator)` returns the unchanged owned accumulator and its count.

Replacement-mode streaming UTF-8 reuses the runtime decoder, including split sequences, one leading BOM, malformed-byte replacement and final incomplete sequences. Canonical `truncateTail` supplies snapshot content and truncation details. Raw/decoded totals, completed/open lines and last-line byte counts preserve upstream behavior. The reversed scalar tail avoids copying retained text on every append; trimming occurs at the same chunk-level threshold and retains the same complete scalar suffix and line-boundary flag. Before a spill, raw chunks occupy at most the configured byte limit after successful appends. Afterward, writes complete before append returns, providing explicit backpressure rather than growing an asynchronous write queue.

A spill is created when raw bytes, decoded bytes or logical line counts exceed their limits, including a limit crossed only by flushing the final UTF-8 replacement in `finish`. All previous raw bytes are written in order before the current stream continues; bytes are never decoded and re-encoded for persistence. Paths use eight OS entropy bytes, the configured prefix, POSIX `TMPDIR`/`TMP`/`TEMP` selection and `/tmp` fallback. Creation is exclusive with mode 0600, so accidental collisions report an error rather than overwriting another file. Files remain available to the caller after close, as upstream expects.

`finish` is idempotent. Closing consumes the file exactly once, including OS close errors, and repeated close is harmless. A failed write retains the handle until checked close. Simultaneous write/close failures retain both errors; failed open/write states reject subsequent mutation instead of silently continuing. Snapshots retain the decoded counts/content for diagnostics. Appending after close returns a typed `Closed` error: upstream instead leaves its path set while clearing its stream, which can silently lose further bytes. Invalid U32 byte values are rejected before changing state. Nonnegative limits are represented by Nat; JavaScript negative/NaN option behavior is not reproduced.

Build `tests/output-accumulator.bend` with the filesystem-byte primitive patch, then run:

```sh
python3 tests/output_accumulator_check.py --runner build/output-accumulator.js
python3 tests/output_accumulator_check.py --runner build/output-accumulator --threads 1
python3 tests/output_accumulator_check.py --runner build/output-accumulator --threads 4
python3 tests/output_accumulator_fault_check.py --runner build/output-accumulator.js
python3 tests/output_accumulator_fault_check.py --runner build/output-accumulator --threads 1
python3 tests/output_accumulator_fault_check.py --runner build/output-accumulator --threads 4
```

The differential harness executes the actual pinned TypeScript source as a test oracle, comparing 383 streaming cases and 7,742 intermediate snapshots per backend, actual temporary-file bytes, path presence and private creation permissions. Coverage includes every byte boundary in UTF-8 samples, BOMs, malformed bytes, empty chunks, zero/default limits, incomplete sequences finished across a limit, random chunking, repeated finish/close, a 200 KB chunk and 2,500 streamed lines. The IO harness reuses the existing filesystem fault hooks to check ENOSPC, EIO/EINTR close failures, simultaneous write/close errors, exactly one close and zero leaked handles, sticky open failure, closed/finished transitions and invalid byte rejection. These are runtime/differential tests, not negative compiler or law tests.

Validation uses ordinary-O1 native builds and explicit `--threads 1`/`--threads 4`, plus Bun. The isolated compiler dependency is `patches/bend-filesystem-bytes.patch`, SHA256 `a173a0a57aa2f41822a30603af8354096eb7cbc15aeb456f881936d1d5139c7f`, supplying raw `File.write_bytes` and exclusive `File.open_mode("wx")`. No compiler patch is installed by this accumulator change. Pi's process execution and Bash tool remain separate integration work; this module alone does not mark those suites complete.

## Owned streaming session

The same module now supplies `createStream(options, onSnapshot) -> IO(StreamOwner)`, `borrowStream(owner) -> StreamOwner & StreamHandle`, `appendStream(handle, bytes) -> IO(Result<Error, Unit>)` and `finishStream(owner) -> IO(Result<Error, OutputSnapshot & Nat>)`. The final Nat is the current line's decoded byte count. The optional callback has type `Callback<OutputSnapshot, Unit>` and remains caller-owned. External producers must stop before finishing; borrowed handles are invalid after finish returns. Appends racing final callbacks after acceptance closes are ignored without changing output. A callback may append reentrantly, but cannot finish its own publisher because that would await itself.

One persistent publisher settles a coalesced Deferred wake, takes a dirty immutable snapshot and replaces the wake while holding `SerialResource.run`, then invokes user code after releasing that lock. Producers settle only the currently locked wake; the old wake is disposed only after its observation has completed and all those settlements have finished. The first dirty snapshot has no initial delay. Later updates wait until 100 ms from the previous publication's start; time spent in a slow callback counts toward that interval. A dirty final snapshot bypasses the remaining cooldown. Empty streams and clean finishes do not manufacture another callback. Without an observer, no publisher, wake or cooldown timer is created.

Finish first closes acceptance and flushes the UTF-8 decoder under the serial lock, then wakes the publisher and cancels its timer. It joins the publisher before retiring the serial resource or checking the spill-file close. The caller may safely dispose its callback and captured resources after finish returns. A previous write failure remains an error even if close succeeds, and a simultaneous write/close failure retains both errors.

`tests/output-stream.bend` and `tests/output_stream_check.py` exercise leading/trailing/final updates, callback reentry, callback completion before retirement, slow callbacks, four concurrent producers with and without observation, empty streams and a final incomplete-UTF8 replacement. Timing checks distinguish immediate first/final publication and a 100 ms interval from an erroneous additional 100 ms after a 140 ms callback. Fault injection checks checked-close EIO/EINTR, prior write plus close errors, failed open, exactly one close and zero leaked file handles. Bun and ordinary-O1 native execution with explicit one/four workers each pass five repetitions of all eight lifecycle scenarios plus those fault audits. The original 383-case/7,742-snapshot differential suite remains green on Bun after adding the streaming layer.

```sh
python3 tests/output_stream_check.py --runner build/output-stream.js
python3 tests/output_stream_check.py --runner build/output-stream --threads 1
python3 tests/output_stream_check.py --runner build/output-stream --threads 4
```
