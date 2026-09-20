# Owned buffered HTTP bodies

`http-body-consume.bytesWith`, `textWith` and `jsonWith` take an affine response body, injectable transport read/close functions and an explicit byte budget. They consume and retire that body. `http-exchange-response.bytes`, `text` and `json` bind these operations to the native socket exchange. No default limit, transport retry, status acceptance or content-type policy is hidden in the consumer; those belong to the caller/provider.

The collector reuses `bounded-bytes`. Successful completion returns every byte in order. The first nonempty excess stops consumption and closes the body; it never returns a truncated success. The budget counts bytes supplied by the HTTP body reader after transfer framing, rather than header or chunk-delimiter bytes. Empty chunks do not spend the budget. Suppressed bodies such as HEAD responses are handled by the existing response owner. Decompression remains separate unfinished work.

The effectful driver closes the body on every returning path. Its pure policy keeps read/limit failure, cleanup failure, or both, without replacing a primary failure with cleanup. Normal HTTP completion and read failures already retire the transport; closing their closed body is idempotent, so callbacks are not invoked twice. A missing completion event is an error, even when some payload was collected. An external transport can remain pending indefinitely; the IO loop does not invent an event/fuel limit or claim unconditional termination.

Text decoding starts only after successful collection and cleanup. It strips one leading UTF-8 BOM and rejects invalid, overlong, surrogate, out-of-range or incomplete sequences using the existing strict decoder. JSON then uses the existing typed parser and returns `schema-value.Value`. The result types distinguish body, UTF-8 and JSON failures. This follows the approved strict-input policy: malformed UTF-8 is rejected rather than replaced as Fetch’s permissive text decoding would do. A transport/cleanup failure takes precedence over a decode failure because partial bodies are not decoded as successful results.

## Correctness evidence

Two additional bounded-byte laws quantify over every input list and spare budget: fitting input survives exactly, and any nonempty excess is rejected. Their supporting induction establishes the complete accumulator state for arbitrary input, budget and previously retained values. Six body-buffer laws preserve arbitrary successful payloads, primary failures and simultaneous cleanup failures; reject a successful prefix on any read error; and stop on every nonempty excess. Together with the existing chunk-composition law, these cover arbitrary chunk divisions without enumerating them.

The [proof gate](proof-validation/2026-09-20-http-body-consume.json) checks 235 public laws and 59 supporting lemmas, rejecting 142 typed mutations. The new IO loop is outside the proof root, and no new unsafe definition supplies proof evidence. These laws do not prove universal scheduler progress or socket retirement.

All 202 [injected-source scenarios](runtime-validation/2026-09-20-http-body-consume.json) pass on native one/four threads and Bun. They assert exact reads, one close, early overflow termination, suppressed bodies, transport and cleanup error precedence, and strict decoding. Every partition of a short Unicode payload is exercised; Python’s standard UTF-8/JSON codecs supply successful decoded-value projections, including binary64 bits and nested values. These are finite integration checks complementary to the generic laws.

All 90 [live socket checks](runtime-validation/2026-09-20-http-body-consume-native.json) also pass: fifteen cases on native one/four threads and Bun, each with production and audited programs. They cover fixed/chunked/EOF framing, HEAD and 204 body suppression, empty bodies, BOM handling, truncated framing, strict decode errors and early byte-limit closure while the peer withholds EOF. Peers observe closure; native audits report no live channels, parked IO or sockets in descriptors 0–4095, and Bun audits report no explicit channels or live/waiting IO. The clean integration worktree is pinned to `cd8da50` plus the recorded changed/new modules, excluding pending form-body drafts.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 scripts/check-proofs.py
python3 tests/http_body_consume_check.py
python3 tests/http_body_consume_native_check.py --worktree "$PWD/build/http-resolved-clean"
```

Provider status/retry/error-body integration, TLS, authentication integration, redirects, decompression, pooling and the complete coding-agent/TUI port remain pending. These body APIs do not by themselves constitute Fetch or a completed provider.
