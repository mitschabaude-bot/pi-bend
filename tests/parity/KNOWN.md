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

- **Session selector layout and controls** (`session-keys`): the tree selector's borders, help text, row labels and position counter differ from pi. The tree also labels a system message as `[message]`. Resume plain text matches, but the selected title resets its foreground colour. The tree needs a closer port of upstream rendering and controls.

- **Streaming throughput and TLS handshake** (`stream-paced`, `stream-flood`):
  over a local TLS server (P-256 certificates), Bend's first token now
  arrives before pi's (72-77 ms versus 110-115 ms in `stream-paced`). A long
  answer (10 KB of Markdown with 30 code blocks, 500 deltas) paced at 4 ms
  per delta ends within the bound (last token 2.29-2.63 s versus pi's
  2.17-2.40 s); flooded, it ends at 0.62-0.81 s versus pi's 0.19-0.34 s
  (2026-09-26, 1506c02e, three runs at load average 14-16; the build
  before the marked speed work, 9e991662, ended the flood at 1.30-1.52 s
  in the same runs). Each frame lexes the whole message with the marked
  port; lexing 54 growing prefixes of this answer takes 0.5 s natively (2.7
  s before the speed work; pi's V8-compiled marked is about 0.5 ms for
  10 KB). TLS is no longer the cause: the same
  flood over plain HTTP (a local copy of the scenario without `tls`) ended
  at 0.36-0.38 s versus pi's 0.13 s before the frame work, so TLS adds
  about 80 ms to Bend and 30-40 ms to pi. What remains is mostly copying
  and releasing the accumulated text: each delta appends to a `String`
  that the agent and transcript still hold, so the whole text so far is
  copied (docs/bend-issues.md BEND-046); pi appends in O(1). Removing the
  copy needs either a runtime string concatenation node or a different
  text type in streamed messages. The runner's theme sync used to retheme,
  and so re-render, every transcript entry on each render request. Until
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
  Bend registers all 41 of pi 0.87.1's built-in providers, including both
  Cloudflare providers, Mistral, Amazon Bedrock, Google Vertex and Radius; a bare `--model gpt-5` lists pi's four candidates and
  `--list-models cloudflare` matches pi. Radius (OAuth browser/device login, the dynamic catalog and models.json `oauth: "radius"` gateways) has not been compared in terminal captures yet. The native API-key `/login` flow now saves credentials for registered providers, including Cloudflare's key/account/gateway prompts. Bedrock resolves stored and ambient AWS credentials and its provider login (bearer token, AWS profile or credential chain) is ported; its `/login` terminal flow has not been compared with pi yet.
- **API-key login presentation** (`login-api-key`): The method screen, filtered provider screen, empty API-key prompt and saved notice match pi's terminal captures, including ANSI styling. The unfiltered list differs because upstream includes providers whose native implementations are still missing. Bend masks secret entry while pi 0.87.1 echoes it. The native flow saves the same provider credential and returns to the editor.
- **Fullscreen TUI mode** (`--tui-mode fullscreen`, setting `tuiMode`): alternate-screen startup, transcript scrolling, the jump indicator, and keyboard transcript search match focused terminal captures. Search mouse controls and full input editing, mouse selection, copy-on-select, fullscreen images, and remaining dock/cursor styling are still open.
- **Fullscreen scroll styling** (`fullscreen-scroll`, `fullscreen-indicator-light-custom-key`): Home/End and the configured jump key reach the same content as pi. At the top, Bend resets the background around the scrollbar on a user-message row differently; in the light theme, scrollbar colors also differ. The indicator badge itself matches.
- **Fullscreen exit styling** (`fullscreen-exit`, `fullscreen-turn-exit`): the final visible transcript, dock, and resume hint now match pi in both cases. Bend still paints the blank editor row with an inverse cursor; an untouched exit also uses the active-theme border color where pi uses its initial border color.
- **Settings panel coverage** (`settings`): the native panel has 25 rows where pi has 31 in the test terminal. HTTP idle timeout, warnings, TUI mode, fullscreen exit output, fullscreen scrollbar and fullscreen copy-on-select controls are missing. The auto-compaction footer marker now updates correctly when the setting changes.
- **Marked thinking picker position** (`settings-model-thinking-marked`): the thinking-level panel retains one extra blank row before the header after opening from a model with a saved override. Regular-mode document clipping has been removed; the scoped-model picker and other thinking-settings scenarios now match plain screen content. Settling between the settings/model/level transitions produces matching frames; rapid consecutive Enter keys can leave different scrollback from intermediate panels.
- **Theme preview header redraw** (`settings-theme-marked`, `settings-theme`, `settings-theme-save`): user-theme startup notices now match, including filename/content-name differences, expanded paths, quiet startup and reload refresh. Previewing a different theme can restore header rows that pi leaves in scrollback; preview/save ANSI styling also differs.
- **Model picker ANSI row resets** (`hotkeys-custom-binding`, `model-selector-all-filter`, `scoped-models-selector`, `scoped-models-controls`): the configured model-select key works and plain screen content matches. The native main-screen renderer places a few ANSI resets at the starts of following rows instead of at the ends of the preceding rows.
- **Resumed large session startup latency** (`large-session-typing`): the terminal capture now matches after moving restored messages behind tool setup. Reaching the editor after the resume prompt was still about six times slower than pi in the measured run; individual keystrokes painted at similar speed.
- **RPC command ordering around a prompt** (`steer-and-queue`): Node runs a
  prompt's microtasks up to its first awaited I/O before reading the next
  stdin line, so a steer sent right after the prompt response arrives while
  the model streams. Bend's RPC reader waits for the prompt's user message
  (the loop has then polled the steering queue) or the prompt's end. When a
  prompt first compacts, pi reads the next command during the compaction
  request instead; Bend still waits for the user message.
