# AgentSessionRuntime over a faux provider

`tests/agent-session-runtime.bend` hosts the faux-provider fixture of `tests/agent-session.bend` in `core/agent-session-runtime.bend` (upstream `agent-session-runtime.ts`): the factory prints each request (cwd, session file, `session_start` reason and previous session file) and builds a fresh agent and AgentSession for it; the release callback disposes the fixture's services after the host disposed the session. `tests/agent_session_runtime_check.py` runs it on Bun and native one/four threads:

- `persisted`: the initial runtime is created without a start event; `newSession` creates a new persisted session in the current session directory only after tearing the old one down, calls the rebind hook with the new session, and records `{reason: "new", previousSessionFile}`; `switchSession` resumes the first session (its two entries intact) with `{reason: "resume"}`; `newSession(parentSession)` writes the parent into the header; switching to a stored session whose cwd no longer exists fails with upstream's `MissingSessionCwdError` message before teardown, so the current session stays; switching back to the second session restores it; `fork` refuses an unknown entry, clones at the leaf (`ForkAt`, a branched file whose header names the source) and forks before the first user message (`ForkBefore`, an empty child session, the message text returned).
- `memory`: a new session from an in-memory session stays in memory; clone and fork run on the outgoing in-memory state after teardown, as upstream reuses its session manager.

Build: `bun build/bend-native-toolchain/bend2/main.ts tests/agent-session-runtime.bend -o build/agent-session-runtime.js` and `BEND_TUS=4 sh scripts/build-pure.sh tests/agent-session-runtime.bend build/agent-session-runtime`.

Not ported: extension events (`session_before_switch` cancellation, `session_shutdown`, `session_start`), `importFromJsonl`, and `withSession`/`setup` callbacks.
