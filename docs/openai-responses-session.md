# Owned asynchronous Responses sessions

`api/openai-responses-session.bend` creates the canonical assistant event stream and starts the existing outer driver as an asynchronous producer. `start` returns an affine `Run` owner without waiting for acquisition or the first event. `borrow` returns that owner unchanged alongside the canonical stream handle, so existing iterator and final-message APIs apply directly.

The producer owns two callbacks: canonical event publication and final stream closure. It retires both after the driver returns, before settling its task result. The supplied acquisition and processing actions are transferred to the producer. Their borrowed callback handles and the signal callback remain caller-owned; processing must finish its uses of the publication handle before returning. The publication callback always returns success after `EventStream.push`; extensions do not replace that private callback. Fallible emission remains an explicitly injectable lower-level driver behavior.

There are two useful completion boundaries. The stream's repeatable `resultValue` returns the final assistant message and may settle before producer cleanup finishes. `Session.wait` joins the producer, retains the full typed lifecycle result, and returns a `Finished` owner. Waiting again on that owner is pure and returns the same result without reading another channel. `dispose` also waits if necessary, then retires the canonical stream and its completion/extraction callbacks. Consumer iterators and borrowed stream operations must finish before owner disposal. Cancellation continues to use the caller's supplied signal; disposal does not silently change cancellation policy.

## Correctness evidence

Ten generic laws specify exact publication and final-result handoff, preservation of the owner/task/stream/result while borrowing, effect-free repeated waits, callback retirement before returning, and joining before stream disposal. These quantify over arbitrary argument, diagnostic and error types, streams, callback handles and run results. The [proof gate](proof-validation/2026-09-21-openai-responses-session.json) checks 293 public laws and 59 supporting lemmas and rejects 168 well-typed mutations. Five new mutations drop publication, omit the final result, leak a publication callback or stream, or add effects to an already-completed wait. These are IO-program and state-transition equalities, not universal scheduling or termination proofs.

The [Bend ownership fixture](runtime-validation/2026-09-21-openai-session.json) uses gated acquisition and an affine channel-backed body. All assertions run in Bend; Python compiles and invokes it. Seven scenarios run on native one/four threads and Bun, in production/audited builds: 42 scenario executions in six processes. They check return before gated acquisition completes, two registered final-result observers plus later observation, repeated owner waits, immutable retained messages, typed acquisition/processing/cleanup/cancellation outcomes, exactly one retirement per acquired body, borrowed-signal survival and disposal while the producer is still running. Audits find no remaining channels, parked IO or sockets.

The [HTTP integration](runtime-validation/2026-09-21-openai-provider-session.json) composes the session with real request uploads, canonical hooks/retries, owned SSE/JSON processing and concurrent stream iterator/result consumers. Fifteen cases run on native one/four threads and Bun in production/audited builds: 90 executions. The oracle is the existing pinned payload-selection-through-catch/end block and actual Responses processor; event snapshots are cloned to model the approved immutable-event policy. Test adapters select string presentation for internal typed causes. Cleanup failures injected after real resource retirement remain separate from the primary cause, and response-hook failure closes the unread owner. Canonical publication cannot produce the injected sink failures tested separately by the lower-level driver fixture.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 scripts/check-proofs.py
python3 tests/openai_session_check.py
python3 tests/openai_provider_session_check.py --worktree build/http-resolved-clean
```

The HTTP record retains a clean source closure excluding pending form-body drafts. Both production modules and all test oracles remain separate: no host-language code supplies provider behavior. No compiler patch is changed or installed.

This owner supplies the asynchronous execution and cleanup machinery for the eventual public provider entry point. Concrete production request preparation, complete typed HTTP-error presentation, authentication/TLS and dispatch still need assembly. The HTTP fixture uploads a test payload; it does not establish a live native model call. The full coding-agent/TUI port and original provider suites remain unfinished, and this milestone promotes no upstream suite status.
