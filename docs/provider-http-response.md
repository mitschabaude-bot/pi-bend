# Provider HTTP status boundary

`packages/ai/src/utils/provider-http-response.bend` separates response ownership from provider error rendering. `acceptWith` returns every successful response with its original affine body, without reading it or applying the diagnostic budget. Failed statuses consume and close their body through the existing bounded strict text consumer before returning `StatusFailure`. That failure retains response metadata and the complete text-consumption result, including transport, byte-limit, UTF-8 and cleanup errors. `retryFailure` projects status and normally coalesced retry headers into the existing retry API while retaining the provider's original typed error and supplied message.

This follows the OpenAI SDK request boundary with SDK retries disabled, as pi configures it: a successful response returns before stream iteration; a failed status consumes its text before error construction and pi's outer retry loop. Body-presence checks remain with the consumer. Accepting a 204 at this boundary does not imply that the Responses SSE consumer accepts a missing stream body.

Four generic laws cover untouched successful ownership/no body IO, failed-status diagnostic sequencing, preservation of arbitrary diagnostic outcomes, and projection of arbitrary status/header/error values. They quantify over source types, effect functions, metadata and affine owners. The [proof gate](proof-validation/2026-09-21-provider-http-response.json) checks 245 public laws and 59 supporting lemmas and rejects 148 typed mutations, including skipping diagnostic consumption. These are IO-program equalities; they do not prove that arbitrary external sources terminate. The adapter imports the existing unsafe body-consumer loop into the proof closure, bringing the exact audited annotation list to eight. Proofs do not use that loop's termination as evidence.

The [injected-source checks](runtime-validation/2026-09-21-provider-http-response.json) run 569 scenarios on native one/four threads and Bun. They cover every status from 100–599, successful handoff with a zero diagnostic budget, caller-driven close/consumption, failed-body close ordering, strict decoding, independent/combined failures, retry metadata and duplicate header coalescing. Generic laws establish the parameterized branch contracts; these executed tests exercise the effectful source and concrete metadata classifiers.

The [native integration checks](runtime-validation/2026-09-21-provider-http-retry.json) compose real HTTP requests, this adapter, the existing affine retry loop and successful text consumption. Fifteen scenarios run on native one/four threads and Bun, in production and resource-audited builds: 90 executions. Peers observe retirement of every connection. Audits report no live channels, parked IO or sockets in the native descriptor range 0–4095; Bun checks channels and live/waiting IO. Eleven ordinary response scenarios also match the installed OpenAI SDK 6.40.0 and pinned pi retry helper directly, including retry overrides, exhaustion, delay hints, lazy success and no-content success. Sleep is an injected trace effect in this fixture; real timer behavior has separate existing evidence.

Malformed diagnostic bodies use an explicit fixture policy: preserve the full typed failure and stop retrying. The shared adapter does not impose that policy or implement SDK APIError formatting. Provider-specific error construction, error-body normalization, response hooks, full request assembly, authentication/TLS and the complete provider/coding-agent/TUI port remain unfinished. Existing permissive retry-delay parsing is unchanged. No additional upstream suite is marked ported by these integration checks.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 scripts/check-proofs.py
python3 tests/provider_http_response_check.py
python3 tests/provider_http_retry_check.py
```

Validation used the existing isolated compiler without changing or installing patches. The native socket composition was built from the recorded committed source closure plus the two new files, excluding unrelated form-body drafts.
