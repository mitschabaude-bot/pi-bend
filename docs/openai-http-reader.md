# Native HTTP Responses reader

`openai-http-responses-reader` composes the native HTTP body source, the existing OpenAI SSE/JSON policy and the typed Responses-event decoder. It lends the existing `openai-responses-stream.Reader<E>` API, preserving the canonical event types and caller-supplied error mapping. It does not replace events with generic JSON or implement a second approximate stream processor.

The caller first accepts the response status and verifies public body presence using its retained metadata, then transfers the affine body to `create`. The provider supplies borrowed abort/diagnostic hooks and keeps them and the parent signal alive until disposal. The owner contains both the provider-reader owner and the HTTP-source owner. Disposal retires them in that order, closing an unread body even when the higher iterator never called its source. Cleanup results retain reader failure, body failure or both. All aliases/in-flight calls must retire before disposal; disposal is not an interrupt for concurrent calls.

`openai-http-errors` recognizes cancellation from native constructors, without string matching. A lone default/supplied socket abort or upload abort without cleanup failure maps to the existing OpenAI `Aborted` branch. Unrelated errors with text such as `AbortError` or `Request was aborted` remain failures. Any combined read/release/disposal/cleanup failure remains a typed failure carrying the original error; cancellation must not erase another cause. The native transport/abort controller retains the reason, while the OpenAI iterator's cancellation branch terminates without throwing, matching the SDK policy.

The reference is installed OpenAI SDK 6.40.0 `core/streaming.mjs`, already used by the project's differential SSE tests. Its iterator suppresses cancellation, drains after a DONE marker, and aborts on early exit or unfinished failure. The existing Bend policy supplies that behavior; this adapter establishes native acquisition and ownership. Invalid JSON invokes the diagnostic hook before abort/error propagation. Typed-wire decoding failure closes the acquired stream. The new combined-cleanup error representation has no direct single-error SDK equivalent; preserving additional failures follows the project's approved strict error policy.

## Evidence

Six generic `http-abort-classification` laws quantify over arbitrary transport error types and classifiers. They delegate lone transport/cleanup classification while excluding combined failures, unexpected events and missing head/completion from cancellation. The [gate](proof-validation/2026-09-20-openai-http-reader.json) checks 227 public laws and 57 supporting lemmas and rejects 136 typed mutations. These laws cover the generic classification rule, not every native wrapper or IO schedule.

All 540 [typed native wrapper combinations](runtime-validation/2026-09-20-openai-http-errors.json) pass per backend on native one/four threads and Bun. They cover default/supplied cancellation, ordinary errors resembling cancellation text, upload cleanup, independent read/release/disposal combinations and protocol incompleteness.

All 72 [live integration executions](runtime-validation/2026-09-20-openai-http-reader.json) pass: twelve cases across the three backends in production and audited programs. Loopback peers feed fixed/chunked/EOF bodies, with seven-byte socket reads and one-byte HTTP chunks. The actual decoder yields typed response IDs and Unicode text deltas, ignores unknown event kinds, drains after DONE and distinguishes malformed JSON, malformed known wire events, API error payloads and transport truncation. Early exit invokes abort once; entirely unread disposal closes the socket without pretending iteration began. Actual pending-read cancellation becomes normal iterator termination. Native audits retire channels, parked IO and sockets in descriptors 0–4095; Bun audits retire explicit channels and live/waiting IO, and peers observe client EOF.

These fixtures use the clean `cd8da50` worktree plus explicitly recorded new files; existing dependencies are verified against the pinned base. Pending form-body drafts are excluded. Proofs use the ordinary pure import closure and do not import those drafts. The [compiler investigation](bend-issues/2026-09-20-openai-http-reader-compiler.json) records the large composition's 8/12 GiB failures, successful 16 GiB build and unsuccessful isolated entry-GC experiment. No compiler change was installed.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 scripts/check-proofs.py
python3 tests/openai_http_errors_check.py --worktree "$PWD/build/http-resolved-clean"
python3 tests/openai_http_reader_check.py --worktree "$PWD/build/http-resolved-clean"
```

This evidence stops at the canonical typed Responses reader. Assistant-message processing over this native transport, provider status/retry/error-body policy, TLS, redirects, decompression, authentication integration and the full coding-agent/TUI port remain unfinished. No authenticated OpenAI-model or complete-provider claim follows from these loopback cases; upstream suite statuses are unchanged.
