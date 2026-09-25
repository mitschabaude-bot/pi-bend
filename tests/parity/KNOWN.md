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
  directory; the runner masks it as `<package>`. Its length also enters
  token estimates, so with an overridden small context window
  `max_output_tokens` differs by the path difference (~26 tokens).
- **Malformed RPC input** (`tests/rpc_session_commands_check.py`): upstream
  reads a missing `sessionPath`/`entryId` unchecked and reports JavaScript's
  TypeError text (`Cannot read properties of undefined (reading 'startsWith')`);
  Bend validates the field. Both fail; the message is not reproduced.
- **Unknown flags with other startup diagnostics** (`print-unknown-flag`):
  upstream collects the unknown-option error with the model-resolution and
  settings diagnostics of the same runtime and prints them together before
  exiting. Bend stops at the unknown option before creating the runtime, so
  a simultaneous model warning or error is not printed. The lone case
  matches.
- **Built-in llama.cpp extension** (`session-settings` RPC flow): pi 0.87.1
  bundles an inline extension that registers the `/llama` command
  (`packages/coding-agent/src/extensions/llama`). The port has no extension
  runtime yet, so `get_commands` lacks it.
- **Built-in provider catalog** (`print-bare-unauthed`, `print-bare-two-authed`):
  Bend registers 5 of pi 0.87.1's built-in providers (openai, openai-codex,
  anthropic, google, cerebras), so a bare `--model gpt-5` has one candidate
  instead of pi's four (azure-openai-responses, cloudflare-ai-gateway, openai,
  opencode). The ambiguity rules themselves are ported and unit-tested
  (`tests/model-resolver.bend`).
- **Syntax highlighting** (colour snaps with code): pi highlights code blocks
  in answers and read/write tool output with highlight.js 10.7 (20 eager
  grammars, the rest loaded in the background). Bend renders them in the
  plain code colour: the port needs an ECMAScript regex engine (captures,
  lookaround, backreferences; Bend's regex is a Thompson matcher for grep),
  the highlight.js mode engine and the grammars, all in Bend. Not started.
- **RPC command ordering around a prompt** (`steer-and-queue`): Node runs a
  prompt's microtasks up to its first awaited I/O before reading the next
  stdin line, so a steer sent right after the prompt response arrives while
  the model streams. Bend's RPC reader waits for the prompt's user message
  (the loop has then polled the steering queue) or the prompt's end. When a
  prompt first compacts, pi reads the next command during the compaction
  request instead; Bend still waits for the user message.
