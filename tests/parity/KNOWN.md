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

- **Streaming throughput and TLS handshake** (`stream-paced`, `stream-flood`):
  over a local TLS server (P-256 certificates), Bend's first token now
  arrives before pi's (72-77 ms versus 110-115 ms in `stream-paced`). A long
  answer (10 KB of Markdown with 30 code blocks, 500 deltas) paced at 4 ms
  per delta ends within the bound (last token 2.21-2.22 s versus pi's
  2.09-2.10 s); flooded, it ends at 0.43-0.47 s versus pi's 0.15-0.20 s
  (7 runs, 2026-09-25). TLS is no longer the cause: the same flood over
  plain HTTP (a local copy of the scenario without `tls`) ends at
  0.36-0.38 s versus pi's 0.13 s, so TLS adds about 80 ms to Bend and
  30-40 ms to pi, and the rest is per-delta event and render work (see the
  native profile: about 45% of the streaming window frees terms). Until
  2026-09-25 the handshake took 350-390 ms and the flood 0.84-0.89 s:
  X25519 used lists of byte limbs (98 ms per scalar multiplication, twice
  per handshake; now sixteen 16-bit limbs in a record, 0.43 ms), AES
  computed each S-box inverse by 13 field multiplications and GHASH went bit
  by bit (21 ms to open 16 KB; now a bitsliced cipher and 32-bit carryless
  products, 1 ms; `tests/tls-crypto-benchmark.bend`), and record bodies
  were buffered byte by byte through closures. RSA-2048 verification also
  went from 97 ms to 13 ms (one-pass Montgomery rows, linear byte
  conversion), which matters for RSA chains; the providers' own chains
  (api.openai.com, chatgpt.com, api.anthropic.com) are ECDSA P-256/P-384.
  Before that, both scenarios took 12-17 s: an expired Bend Timer completes
  at once, so a zero-delay frame timer drew after every one or two deltas
  instead of after the received events, as Node's setTimeout (at least
  1 ms, fired from the event loop) does. `stream-flood` reports
  `slow:last-token` until fixed.

- **Request headers** (every scenario with a model turn): Bend sends neither
  Node fetch's default fields (`accept-encoding`, `accept-language`,
  `connection`, `sec-fetch-mode`; see tests/fetch-keepalive.md) nor the OpenAI
  SDK's platform fields (`x-stainless-arch/lang/os/package-version/runtime/
  runtime-version`). Sending `x-stainless-runtime: node` from a Bend binary
  would misreport the client, so Bend sends none (Gregor, 2026-09-25; headers
  describing pi-bend itself are a possible later addition).
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
  Bend registers 37 of pi 0.87.1's built-in providers, including both
  Cloudflare providers; a bare `--model gpt-5` lists pi's four candidates and
  `--list-models cloudflare` matches pi. Missing: bedrock, vertex, mistral
  and radius (APIs not ported). API-key `/login` (including Cloudflare's
  key/account/gateway prompts) is not ported for any provider.
- **LaTeX in multi-line paragraphs and list items** (answers with math):
  `packages/tui/src/latex.bend` and the Markdown `latex`/`latexBlock` tokens
  match pi on 2,170 cases (`tests/latex_check.py`). The Bend Markdown
  component still renders a paragraph line by line and has no list-item
  continuation model, so a `$` closed on a later line of the same paragraph,
  an unclosed delimiter while streaming (pi shows the rest of the paragraph
  raw, Bend only the rest of the line) and display math inside a list item
  (pi keeps the item indentation) differ; five such cases are tracked as
  known divergences in the check.
- **Fullscreen TUI mode** (`--tui-mode fullscreen`, setting `tuiMode`): the
  arguments parse, but `tui-alt-screen.ts` (alternate screen, scroll view,
  copy-on-select, fullscreen images) is not ported; the default regular mode is.
- **RPC command ordering around a prompt** (`steer-and-queue`): Node runs a
  prompt's microtasks up to its first awaited I/O before reading the next
  stdin line, so a steer sent right after the prompt response arrives while
  the model streams. Bend's RPC reader waits for the prompt's user message
  (the loop has then polled the steering queue) or the prompt's end. When a
  prompt first compacts, pi reads the next command during the compaction
  request instead; Bend still waits for the user message.
