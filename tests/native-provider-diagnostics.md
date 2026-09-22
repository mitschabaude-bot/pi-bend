# Opt-in provider diagnostics in the test host

Set `PI_BEND_PROVIDER_DIAGNOSTICS=1` when running the native four-tool fixture. Its test-only provider lease observes the typed `Responses.RunResult` before calling the unchanged production `Providers.released` helper. Failed primary and cleanup causes print `provider-diagnostic|primary|CATEGORY` and `provider-diagnostic|cleanup|CATEGORY`; ordinary provider/assistant behavior and ownership remain unchanged. Only constructor categories, numeric OS/status codes and existing fixed TLS labels are rendered, never arbitrary provider messages, payloads, JSON paths, headers, credentials or URLs.

The focused local HTTPS test covers malformed SSE JSON, an invalid Responses event, a stream missing its terminal event, and abrupt TLS termination. For every case, absent/disabled/enabled runs must have identical exit status, stderr and stdout after removing diagnostic lines. Missing optional environment variables are handled as disabled; they must not terminate the host. Payload/key sentinels must not appear in diagnostics. The complete seven-scenario native four-tool loop is rerun with observation enabled.

```sh
BEND=/path/to/combined/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/native-edit-agent.bend build/native-edit-agent-diagnostic
python3 tests/native_provider_diagnostics_check.py build/native-edit-agent-diagnostic --threads 1
python3 tests/native_provider_diagnostics_check.py build/native-edit-agent-diagnostic --threads 4
PI_BEND_PROVIDER_DIAGNOSTICS=1 python3 tests/native_edit_agent_check.py native-1 --prefix build/native-edit-agent-diagnostic
PI_BEND_PROVIDER_DIAGNOSTICS=1 python3 tests/native_edit_agent_check.py native-4 --prefix build/native-edit-agent-diagnostic
```

The focused failure/redaction checks and all seven complete tool-loop scenarios pass on optimized native one/four workers. No external requests are made by these tests; a live reproduction is coordinated separately by the root task.

## Explicit request retries in the test host

`PI_BEND_RETRY_REQUESTS=1` sets `maxRetries=2` in this integration host; unset or any other value keeps `maxRetries=0`. This is opt-in request retry, not automatic agent-session recovery. Upstream low-level `packages/ai/src/utils/provider-retry.ts` defaults `options.maxRetries` to zero; full `AgentSession` auto-retry remains unported. The production provider and existing fixture defaults are unchanged.

The same local runner captures an entire HTTPS request, then closes with TCP RST before sending response headers. Unset and explicitly disabled retry must fail after one request with zero tool executions. Opt-in retry must replay the complete HTTP request bytes exactly, receive one write call, then send one normal post-tool request containing exactly one matching call/result. The initial request has two attempts; total HTTP requests are three because the final model turn follows tool execution. File contents, execution counters, event counts and the final answer are checked, and no extra connection may remain queued after shutdown. Existing failure/redaction cases explicitly disable retries so inherited host settings cannot alter their expectations.

The reset test exposed a production classification omission: TLS-wrapped socket failures were terminal even when the corresponding plain socket failure was retryable. `fetch.bend` now delegates `TLSSourceFailure{Network{cause}}` and `TLSStartFailure{Network{cause}}` to its existing socket classifier. `tests/fetch-retry.bend` checks both paths for reset104, deadline expiry, supplied/default cancellation, protocol/certificate/configuration errors, and combined cleanup failure. Only socket failures change; TLS validation and cleanup failures remain terminal.

```sh
sh scripts/build-pure.sh tests/fetch-retry.bend build/fetch-retry
build/fetch-retry --threads 1
build/fetch-retry --threads 4
build/bend-native-toolchain/bend2/main.ts tests/fetch-retry.bend -o build/fetch-retry.js
bun build/fetch-retry.js
```

Validation: all 15 classification assertions pass Bun and native one/four workers. The final combined native artifact passes all 12 diagnostic flag/failure combinations, all three reset/retry settings, and all seven existing four-tool scenarios on one/four workers. The ordinary four-tool runs explicitly unset both optional environment variables. No external requests or compiler changes were used.
