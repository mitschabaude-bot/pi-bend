# Opt-in provider diagnostics in the test host

Set `PI_BEND_PROVIDER_DIAGNOSTICS=1` when running the native four-tool fixture. Its test-only provider lease observes the typed `Responses.RunResult` before calling the unchanged production `Providers.released` helper. Failed primary and cleanup causes print `provider-diagnostic|primary|CATEGORY` and `provider-diagnostic|cleanup|CATEGORY`; ordinary provider/assistant behavior and ownership remain unchanged. Only constructor categories, numeric OS/status codes and existing fixed TLS labels are rendered, never arbitrary provider messages, payloads, JSON paths, headers, credentials or URLs.

The focused local HTTPS test covers malformed SSE JSON, an invalid Responses event, a stream missing its terminal event, and abrupt TLS termination. For every case, enabled/disabled runs must have identical exit status, stderr and stdout after removing diagnostic lines. Payload/key sentinels must not appear in diagnostics. The complete seven-scenario native four-tool loop is rerun with observation enabled.

```sh
BEND=/path/to/combined/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/native-edit-agent.bend build/native-edit-agent-diagnostic
python3 tests/native_provider_diagnostics_check.py build/native-edit-agent-diagnostic --threads 1
python3 tests/native_provider_diagnostics_check.py build/native-edit-agent-diagnostic --threads 4
PI_BEND_PROVIDER_DIAGNOSTICS=1 python3 tests/native_edit_agent_check.py native-1 --prefix build/native-edit-agent-diagnostic
PI_BEND_PROVIDER_DIAGNOSTICS=1 python3 tests/native_edit_agent_check.py native-4 --prefix build/native-edit-agent-diagnostic
```

The focused failure/redaction checks and all seven complete tool-loop scenarios pass on optimized native one/four workers. No external requests are made by these tests; a live reproduction is coordinated separately by the root task.
