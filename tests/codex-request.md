# Native Codex Responses request framing

The Codex SSE endpoint shares native HTTPS, streaming conversion and the agent loop with the standard Responses provider. It uses the stored OAuth bearer token's account claim, the Codex URL and headers, and a distinct request body. The modular CLI live lane is described in [print-cli.md](print-cli.md).

`codex_request_check.py` compares 120 complete results with the actual pinned `openai-codex-responses.ts` request builder. Cases combine system instructions, tool declarations/redefinitions/removal, mid-conversation systems, additional tools/tool search, and absent/enabled/disabled strict-mode support. This caught and corrected Codex's default support flag and explicit null strictness, without changing the standard Responses policy. It also verifies low verbosity, encrypted reasoning inclusion, parallel calls, cache session identity, temperature/service tier, reasoning and omission of output-token/cache-retention fields. The 372 standard Responses preparation comparisons remain a separate regression gate.

```sh
BEND=/path/to/patched/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/codex-request.bend build/codex-request
/path/to/patched/bend2/main.ts tests/codex-request.bend -o build/codex-request.js
python3 tests/codex_request_check.py
```

This is endpoint integration, not complete Codex-provider parity. The native shared options currently use low text verbosity; the Codex-specific public options surface, WebSocket/session-cache behavior, complete error-policy differences and interactive OAuth login still need porting. The oracle covers body construction and is not evidence for those missing contracts or for the original streaming/OAuth suites. JWT payload inspection extracts a routing claim; it does not authenticate a token locally or verify a signature.
