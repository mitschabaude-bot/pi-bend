# OpenAI Responses provider

Upstream: `packages/ai/src/api/openai-responses.ts` and `openai-responses-shared.ts` at pi-mono `46c9de402`, with the `openai` SDK 6.40.0 client and streaming code they depend on. The native port is five modules under `packages/ai/src/api` plus the runtime fetch:

| Module | Upstream counterpart | Contents |
| --- | --- | --- |
| `openai-responses.bend` | `openai-responses.ts` | `OpenAIResponsesOptions`, compat/cache policy, `getClientApiKey`, client headers, `buildParams`, `prepare`, `applyServiceTierPricing`, the `Error` sum and `describe`, lifecycle (`check`, `complete`), `Config`/`Transport`, acquisition through `retryProviderRequest`, hooks, the `Run` owner and `stream`/`streamAt`/`streamSimple` |
| `openai-responses-shared.bend` | `openai-responses-shared.ts` (conversion half) | text signatures, message/tool conversion, item IDs, assistant replay, `ReplayContext` |
| `openai-responses-stream.bend` | `openai-responses-shared.ts` (`processResponsesStream`) | output items, slot state, terminal handling, service-tier resolution, wire decoding, the processor over an affine iterator state |
| `openai-client.bend` | SDK client (`buildHeaders`, `buildURL`, `APIError`, one request) | request headers and authentication policy, Responses URL, request envelope, typed `APIError`, one attempt with retry classification, body release |
| `openai-sse.bend` | SDK `Stream.fromSSEResponse` | dispatch policy (`step`), the affine `Cursor` with abort/diagnostic hooks, body acquisition and disposal |
| `packages/runtime/src/fetch.bend` | `fetch` | native cleartext HTTP over the runtime resolver, hosts file and connection driver; retry `Category` classification |

Public type, field, function and event names follow upstream where Bend permits. The six utility modules (`constrained-sampling`, `github-copilot-headers`, `openai-prompt-cache`, `simple-options`, `transform-messages`, `transform-tool-results`) are unchanged; the strict-schema pass now lives inside `constrained-sampling.bend`.

## Language-driven changes

- **Pure pricing hooks.** `resolveServiceTier`/`applyServiceTierPricing` are pure templates over immutable usage values instead of callbacks mutating `usage` in place. An unchanged usage means no tier pricing applied; the hooks cannot fail.
- **Affine iterator state.** `processResponsesStream` takes `~next`/`~close`/`~emit` templates over a caller-owned state `S` instead of an async iterator and a mutable sink. The provider's state is the acquired body, its SSE cursor and the canonical event stream; every read, emission and close is a typed state transition.
- **Typed errors.** `throw` sites become the `Error` sum; `describe` renders the assistant `errorMessage`. Hook errors are caller-typed (`E`) and rendered by the caller. JSON parse failures carry the native parser error, so the message is `Invalid SSE JSON: …` rather than V8's `SyntaxError` text.
- **Ownership.** The run is an owner (`Run`): `borrow` its event stream, `wait` for the settled result, `dispose` after consumers finish. A supplied signal is never disposed by the provider; a local controller is retired after settlement. The native transport is created per request and retired after the body is disposed; a custom `fetch` callback is borrowed.
- **Retry effects are real.** Entropy, the HTTP date parser and timer sleeps are owned by the acquisition loop, so traces no longer print injected `random`/`sleep` effects.
- **Strict retry options.** A non-integer `maxRetries` or invalid `maxRetryDelayMs` fails preparation after the payload hook with a typed cause instead of behaving as upstream's `NaN` arithmetic.

## Laws

`laws/openai-responses.bend`, `laws/openai-responses-stream.bend`, `laws/openai-sse.bend`, `laws/openai-client.bend` and `laws/fetch.bend` state the invariants that matter: cancellation precedes stop validation and never replaces an existing failure, failure preserves every other message field, a cancelled or rejected request never opens a transport, an acquisition failure never reaches the hooks, disposal failures never replace the processing outcome, the options extension is lossless, caching policy, service tiers that do not reprice, the SDK's `[DONE]`/`thread.*`/truthy-`error` dispatch policy, authentication policy and timeout validation, `APIError` evidence retention, and the retry classification of transport failures (only deadline expiry is a timeout, only silence is a connection failure, cancellation is never retried). They replace the earlier wrapper-equality laws of the retired layer modules.

## Validation

- `python3 tests/openai_responses_check.py` builds `tests/openai-responses.bend`, scripts a loopback HTTP server per case and compares every printed line with the pinned upstream wrapper (`tests/openai_provider_driver_reference.mts`) driven by the same events: hooks, run outcome, retained events, final message, tool arguments from a grammar tool, timestamps and cancellation. Cases cover payload/response hook failures and replacement, partial and malformed streams, failed/incomplete responses, 503 retries and exhaustion, invalid retry options, pre-aborted signals, service tiers, a missing API key, a broken resolver configuration, the default `stream` entry and a slow body. `--audit` adds channel/socket/timer/file audits.
- `tests/responses_*` and `tests/openai_sse_*` compare the pure stages with the SDK and pi; `tests/openai_http_error_check.py`, `openai_request_headers_check.py`, `openai_responses_envelope_check.py`, `openai_responses_url_check.py` and `openai_service_tier_check.py` cover the client and pricing.

## Limitations

Native TLS is unfinished, so the provider runs only over cleartext HTTP; authentication flows, WebSocket transport and the other providers are not ported. The tier hooks cannot fail, so upstream's failing-hook cases have no native equivalent.
