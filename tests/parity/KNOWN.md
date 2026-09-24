# Known differences in parity runs

`tests/parity/runner.py` diffs every screen, output and model request. A
difference is either listed here with its reason or it is a bug. Each entry
names the scenario where it shows; the runner masks the header and aliasing
entries (`KNOWN_HEADERS`, `ALIASED_EVENTS`) so a run reports only the rest.

## Language-driven (the port does not reproduce them)

- **JSON key order** (`json-turn`): JavaScript serialises object keys in
  insertion order, which depends on when a provider assigns `responseId`,
  `rawStopReason`, `errorMessage`. AGENTS.md excludes reproducing JS key
  enumeration; the runner compares JSON lines as values.
- **Aliased partial messages** (`json-turn`): upstream providers push `start`
  and `*_delta` events with the same mutable `output` object they keep
  filling, and JSON mode serialises events after the stream has moved on, so
  pi's `message_start`/`message_update` already show the final `usage` and
  `responseId`. Bend's events carry the values of their moment. This is
  incidental reference identity.

## Open (to fix)

- **Request headers** (every scenario with a model turn): Bend sends neither
  Node fetch's default fields (`accept-encoding`, `accept-language`,
  `connection`, `sec-fetch-mode`; see tests/fetch-keepalive.md) nor the OpenAI
  SDK's platform fields (`x-stainless-arch/lang/os/package-version/runtime/
  runtime-version`). Sending `x-stainless-runtime: node` from a Bend binary
  would misreport the client; awaiting Gregor's decision.
- **Docs path** (`basic-turn` requests): the system prompt names the install
  directory; the runner masks it as `<package>`.
- **Malformed RPC input** (`tests/rpc_session_commands_check.py`): upstream
  reads a missing `sessionPath`/`entryId` unchecked and reports JavaScript's
  TypeError text (`Cannot read properties of undefined (reading 'startsWith')`);
  Bend validates the field. Both fail; the message is not reproduced.
