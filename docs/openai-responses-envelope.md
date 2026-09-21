# Native Responses request envelopes

`api/openai-responses-envelope.bend` combines native Responses URL preparation, JSON serialization and OpenAI header assembly into an immutable unframed request. Its request value retains the typed URL, lowercase `post` method, normalized headers, serialized body and effective timeout. This is the SDK buildRequest stage: fetch dispatch must uppercase the method before invoking custom fetch (the SDK does so in fetchWithTimeout). Native HTTP subsequently derives Host, encodes UTF-8 and frames the body. No socket, timer, callback or signal owner is acquired by this pure component.

Callers pass the payload chosen by `onPayload`. The envelope does not invoke or retry the hook. Validation follows SDK request-preparation order: URL, timeout, body, then headers. Typed errors retain the originating URL/header cause, distinguish non-finite payloads from encoding failure, and bypass later validation after a failure. SDK retries remain disabled, so the retry-count header is zero; the existing provider retry loop remains the owner of retry policy.

The JSON serializer's `Content-Type: application/json` layer overrides client-default content type. Pi passes its configured headers as SDK client defaults, not as per-request serializer options; configuring a different default content type therefore does not switch a JSON payload to form encoding. The native implementation preserves that meaningful distinction.

The effective default timeout is 600,000 ms, but an omitted timeout emits no `X-Stainless-Timeout` header. Explicit zero also omits that header; other explicit valid integer values are converted to truncated seconds by the shared header layer. The SDK's `buildRequest` computes the effective timeout on a copied options record while `buildHeaders` receives the original options. The integrated actual-SDK comparison revealed this distinction; the earlier isolated header harness had supplied an effective timeout explicitly. The envelope calls the staged header layer with the original timeout specification rather than confusing that specification with its effective value.

## Native payload semantics

Explicit JSON `null`, `false`, zero and the empty string remain present bodies. SDK 6.40.0's truthiness-based dispatch can omit them; that accidental distinction is not reproduced. JSON quoting and numeric spelling otherwise use the existing native serializer. A pure numeric-leaf validator rejects NaN and infinities anywhere in the payload before encoding, instead of silently converting those values to `null`.

`utils/json-finite.bend` traverses immutable values directly. It selects continuation functions lazily so array/object tails are tail calls on the JavaScript backend. The previous eager boolean expression reproduced BEND-019 at 65,536 entries; the reduced before/after record is retained. The revised traversal adds no unsafe declaration. The growth test establishes wide-container behavior on native one/four threads and Bun, not an unbounded runtime-stack guarantee for arbitrarily deep trees.

Seven finite-value laws cover numeric classification, invalid numeric leaves, array/object composition and array partitioning. Eight envelope laws preserve encoded text and completed fields, reject invalid payloads, preserve typed errors and establish validation precedence and omitted-timeout behavior. Two supporting boolean lemmas bridge lazy evaluation to the unchanged declarative conjunction contracts. Encoding correctness and full request assembly also rely on executed comparisons; these laws are not presented as a proof of the entire JSON codec or SDK.

## Scope and remaining work

The fixture executes actual SDK `buildRequest` with fake credentials and no network. Platform metadata is injected explicitly from that oracle for comparison; production callers must provide native Bend identity. It retains raw SDK falsy-body omission, non-finite conversion and empty-base fallback alongside the approved native results. A separate serialization probe obtains SDK JSON-header precedence for the explicit-present-body cases without concealing the original SDK output.

The [Responses fetch adapter](openai-responses-fetch.md) now connects this envelope to borrowed injectable callbacks, exact native timeout validation and response ownership. Actual native transport selection and retry/status/asynchronous-session assembly remain pending. Native TLS/auth refresh, complete other-provider support, agent/TUI parity and native extensions remain unfinished. No upstream pi suite status changes.

## Validation

The [proof record](proof-validation/2026-09-21-openai-responses-envelope.json) checks 371 public laws and 64 supporting lemmas, rejects 207 well-typed mutations, and verifies open-obligation and missing-proof rejection. The existing 13-declaration unsafe source audit is unchanged. The [runtime record](runtime-validation/2026-09-21-openai-responses-envelope.json) contains 229 request cases on native one/four threads and Bun, totaling 687 comparisons, with 86 intentional differences retained alongside raw SDK results. Cases cover primitive/structured payloads, nested non-finite numbers, header precedence and validation, explicit/default/invalid timeouts, URL/query errors, Unicode hosts and organization/project settings. Separate 65,536-entry array/object growth checks pass on all three backends.

The unchanged isolated compiler produced the final native fixture in 885.15 seconds, including Clang `-O1`, with a sampled group peak of 13,211,712 KiB. JS emission took 14.96 seconds at 6,808,228 KiB. Generated C is 32,111,563 bytes. The [compiler record](bend-issues/2026-09-21-openai-responses-envelope-compiler.json) retains source/compiler hashes and phase measurements. These are observations of a larger composed workload, not a controlled performance comparison; no compiler patch was changed or installed.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 scripts/check-proofs.py
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 tests/openai_responses_envelope_check.py
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 tests/json_finite_growth_check.py
```

The envelope runner guards native/JS rebuilds at 24/12 GiB. `--no-build` requires source-verified existing artifacts; `--js-only` is partial validation and does not emit the full runtime record. The historical URL oracle correction has its own retained record and does not require rebuilding unchanged URL artifacts.
