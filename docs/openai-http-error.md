# Typed OpenAI HTTP errors

`api/openai-http-error.bend` constructs an immutable `APIError` from the owned HTTP status adapter's failure. It retains response metadata, a text or JSON diagnostic, and the SDK-style message. Error kind, status, request ID and structured code/param/type fields have native projections; `retryFailure` retains the same typed error in pi's canonical retry result. Diagnostic read/cleanup failures remain typed construction failures and are never converted into a successful error-body string.

An ordinary JSON error envelope selects its `error` value. Non-JSON gateway text is kept verbatim in the SDK-style message. That text is deliberately not supplied again as a separate body candidate to pi's normalizer: the OpenAI SDK only stores it in `message`, and adding a body candidate would change long-message truncation. Structured diagnostics use the existing `error-body` module's parsed-body path. `format` applies the same OpenAI/custom-provider prefix as pi's Responses catch block.

Following the native-value policy, JSON diagnostics do not disappear because of JavaScript truthiness or an absent envelope field. False, zero, empty-string and null error values remain representable; unrecognized gateway JSON retains its full value. False/zero message values serialize explicitly. The validation record retains the original SDK outputs alongside declared differences. These are diagnostic information-preservation changes, not SDK object/prototype emulation. Existing JSON numeric serialization remains shared with the canonical JSON codec; this adapter does not redefine its number domain.

Nine generic laws preserve arbitrary metadata, diagnostics, read failures, envelope selections, message text, normalization inputs and original retry errors. Five additional `text-unit-budget` laws prove chunk composition, prefix stability after exhaustion, fitting-character retention, nonfitting-character exclusion and the empty-input boundary. The [gate](proof-validation/2026-09-21-openai-http-error.json) checks 259 public laws and 59 supporting lemmas, rejecting 153 typed mutations. No unsafe annotation was added to the proof closure.

The [codec/normalization checks](runtime-validation/2026-09-21-openai-http-error.json) run 2,966 scenarios on native one/four threads and Bun. They include 388 exact comparisons against OpenAI SDK 6.40.0 and pinned pi's actual error normalizer, ten declared diagnostic/character-boundary adaptations, read/encoding failure projection, all unit budgets of short mixed-width strings, and 100,000 ASCII/20,000 emoji inputs. The [existing utility regression](runtime-validation/2026-09-21-error-body-regression.json) retains 306 comparisons per native thread count and all sixteen original named scenarios; two supplemental split-surrogate boundary expectations are explicitly adapted.

The [real HTTP checks](runtime-validation/2026-09-21-openai-http-error-native.json) exercise native response acquisition, bounded diagnostic consumption and typed normalization together. Fifteen cases run on native one/four threads and Bun, in production and resource-audited builds: ninety executions. They cover ordinary SDK diagnostics, nested OpenRouter extras, Unicode/chunking/BOM decoding, plain text, unknown JSON, read limits, truncation, invalid UTF-8 and successful/no-content handoff. Peers observe closure. Native audits check live channels, parked IO and sockets in descriptors 0–4095; Bun audits explicit channels and live/waiting IO.

## Native character budgets

The previous error normalizer represented UTF-16 units as invalid Bend characters. Bun rejected that construction even for ASCII because the unused `Bool.pick` branch was eagerly evaluated. `runtime/text-unit-budget.bend` now counts one/two UTF-16 units per native character and keeps a complete-character prefix. It never manufactures a surrogate. If a cap falls inside an emoji, the whole emoji is omitted, and the truncation notice counts all actually discarded units. This deliberately differs from JavaScript's lone-surrogate slice. Literal invalid-character construction elsewhere remains the separate BEND-021 compiler discrepancy; no compiler patch was made.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 scripts/check-proofs.py
python3 tests/openai_http_error_check.py
python3 tests/openai_http_error_native_check.py
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 tests/error_body_check.py
```

Full provider request assembly, payload/response hooks, typed construction-failure presentation in the final stream, authentication/TLS and coding-agent/TUI parity remain unfinished. The provider-error-body regression suite still requires the actual provider catch paths; these lower-level checks do not promote that suite or complete the shared error-body suite's remaining provider adaptations.
