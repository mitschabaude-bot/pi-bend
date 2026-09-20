# Provider request hooks and ownership

`utils/provider-request.bend` composes the canonical payload and response callbacks around the existing owned retry loop. `onPayload` runs once before any request; an absent replacement preserves the input, while a present replacement is used exactly, including null or zero. Every retry receives that same immutable payload. `onResponse` runs once after successful acquisition, before body consumption. Neither hook failure enters the request retry loop.

The request callback returns an affine response owner. `utils/provider-response-view.bend` projects canonical status and headers while returning the entire response unchanged. Success transfers the owner to the caller. A response-hook failure releases it before returning a typed error that retains both the hook cause and cleanup outcome. Supplied callback handles remain borrowed; the temporary fixed-payload callback is disposed before response-hook dispatch. Error types remain caller-selected native values.

This preserves the pinned OpenAI Responses request-stage ordering without introducing a second retry implementation. Native callbacks return an explicit optional replacement instead of mutating a JavaScript payload. On response-hook failure, explicit owner retirement improves the upstream path, whose catch block does not explicitly close the acquired, unread stream. Cleanup failures remain separate from the original hook failure, following the accepted typed-error/lifecycle policy.

Eight generic request laws preserve arbitrary payload replacements and failures, prove absent-hook and failed-request dispatch boundaries, and specify successful owner transfer and release-before-failure as IO-program equalities. A ninth law preserves the affine response during metadata projection. The [proof gate](proof-validation/2026-09-21-provider-request.json) checks 268 public laws and 59 supporting lemmas and rejects 157 typed mutations. These are branch and composition guarantees, not a termination theorem for arbitrary callbacks or a universal resource-leak proof.

The [integration record](runtime-validation/2026-09-21-provider-request.json) contains 84 real HTTP executions: fourteen cases on native one/four threads and Bun, with production and resource-audited builds. The oracle executes the exact request-stage block extracted from pinned pi's `openai-responses.ts` with its actual retry helper and header projector. Cases cover absent hooks, unchanged/replaced/null/zero payloads, retry/exhaustion/terminal statuses, metadata coalescing, and hook/cleanup failures. Peers verify uploaded JSON and connection closure. Native audits check channels, parked IO and socket descriptors 0–4095; Bun audits explicit channel and IO state. Native cleanup/result markers are separately specified and are not claimed as upstream oracle output.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 scripts/check-proofs.py
python3 tests/provider_request_check.py --worktree build/http-resolved-clean
```

The recorded clean import closure excludes the unrelated pending form-body drafts. This stage still needs composition with concrete provider serialization, typed OpenAI error construction and the Start/Done/Error stream wrapper. Authentication/TLS, other providers and coding-agent/TUI parity remain unfinished. No upstream suite status is promoted by this milestone.
