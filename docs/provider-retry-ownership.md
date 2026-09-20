# Retry success values and ownership

The existing provider retry loop now abstracts over Bend’s value quantity. `retryProviderRequestWith` accepts `Value: Kind(v)` and carries that quantity through its result and internal decision types. The existing `retryProviderRequest` API specializes the loop to copyable data and keeps its signature. `retryProviderRequestOwned` specializes the same loop to affine values, allowing a native response/stream/socket owner to pass directly to its caller. No second retry engine or shared-reference wrapper around the successful owner is introduced.

Retry policy, attempts, delay effects, error preservation and abort precedence are unchanged. A success returns immediately, even if the caller’s signal was already aborted; this matches pi’s generic helper, whose request callback itself is responsible for honoring its signal. A failed request checks abortion before exhaustion, and only typed provider failures enter retry policy. The callback must retire resources belonging to failed attempts. The successful affine owner belongs to the recipient, which must eventually retire it. The retry loop cannot clean up a resource that a callback hides rather than returning.

Six generic laws quantify over arbitrary value quantities, value/error/reason types, values, effect handles, options and continuations. They establish that success bypasses retry effects, completion bypasses the continuation, retry invokes that continuation, abortion stops a failed request, exhaustion retains its original failure, and application failures are not retried. These are IO-program equalities, not claims that an arbitrary request or effect always terminates. The [gate](proof-validation/2026-09-21-provider-retry-owned.json) checks 241 public laws and 59 supporting lemmas and rejects 145 typed mutations. No new unsafe annotation enters the proof root.

All 72 [real-socket executions](runtime-validation/2026-09-21-provider-retry-owned.json) pass: twelve scenarios on native one/four threads and Bun, each in production and audited programs. Expected retry/effect traces come from the actual pinned pi helper, supplemented with explicit acquisition/close markers. Failed attempts close their sockets before retry; the eventual successful socket remains writable, sends its payload exactly once and is closed by the recipient. Peers observe the corresponding payloads and EOF. Native audits check channels, parked IO and sockets in descriptors 0–4095; Bun audits check explicit channels and live/waiting IO. These are finite lifecycle checks.

The [regression record](runtime-validation/2026-09-21-provider-retry-regression.json) retains all twelve original data-result traces on native one/four threads and Bun, all five named upstream tests on native one/four threads, the virtual-clock sensitivity control, and rejection of an attempted copy of the affine result. The original timer code remains unchanged. The installed compiler was not modified; all runs identify the existing isolated candidate.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 scripts/check-proofs.py
python3 tests/provider_retry_owned_check.py
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 tests/provider_retry_check.py
python3 tests/provider_retry_named_check.py build/bend-profiles/dns-transport-teles/bend2
```

This resolves the retry success-type restriction needed for native provider integration. HTTP status/error-body projection into provider errors, full request assembly, TLS/authentication integration and the complete provider/coding-agent/TUI port remain unfinished. The socket fixture supplies failures explicitly and does not claim HTTP status-handling coverage. Existing retry-header parsing and delay policy are unchanged by this ownership generalization.
