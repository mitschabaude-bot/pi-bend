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
  per delta ends with pi's (last token 2.05-2.09 s versus pi's
  2.07-2.11 s); flooded, it ends at 0.36-0.40 s versus pi's 0.16-0.19 s
  (7 runs, 2026-09-25; before the frame work below 2.18-2.24 s and
  0.42-0.46 s at the same base). TLS is no longer the cause: the same
  flood over plain HTTP (a local copy of the scenario without `tls`) ended
  at 0.36-0.38 s versus pi's 0.13 s before the frame work, so TLS adds
  about 80 ms to Bend and 30-40 ms to pi. What remains is mostly copying
  and releasing the accumulated text: each delta appends to a `String`
  that the agent and transcript still hold, so the whole text so far is
  copied (docs/bend-issues.md BEND-046); pi appends in O(1). Removing the
  copy needs either a runtime string concatenation node or a different
  text type in streamed messages. Frames are now cheap. A full render of
  the 10 KB answer still takes 32-36 ms natively against pi's 6 ms, but a
  streaming frame reuses the finished lines of every unchanged Markdown
  block from the previous frame (`Markdown.Memo`), so the 40 growing
  frames of a benchmark take 3 ms each where they took about 17 ms, and pi
  re-renders in 1-6 ms. Before, the runner's theme sync also rethemed, and
  so re-rendered, every transcript entry on each render request. Until
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
  and radius (APIs not ported). The native API-key `/login` flow now saves credentials for registered providers, including Cloudflare's key/account/gateway prompts; Bedrock remains unavailable because its provider is missing.
- **API-key login presentation** (`login-api-key`): The method screen, filtered provider screen, empty API-key prompt and saved notice match pi's terminal captures, including ANSI styling. The unfiltered list differs because upstream includes providers whose native implementations are still missing. Bend masks secret entry while pi 0.87.1 echoes it. The native flow saves the same provider credential and returns to the editor.
- **LaTeX in multi-line paragraphs and list items** (answers with math):
  `packages/tui/src/latex.bend` and the Markdown `latex`/`latexBlock` tokens
  match pi on 2,170 cases (`tests/latex_check.py`). The Bend Markdown
  component still renders a paragraph line by line and has no list-item
  continuation model, so a `$` closed on a later line of the same paragraph,
  an unclosed delimiter while streaming (pi shows the rest of the paragraph
  raw, Bend only the rest of the line) and display math inside a list item
  (pi keeps the item indentation) differ; five such cases are tracked as
  known divergences in the check.
- **Fullscreen TUI mode** (`--tui-mode fullscreen`, setting `tuiMode`): alternate-screen startup, transcript scrolling, the jump indicator, and keyboard transcript search match focused terminal captures. Search mouse controls and full input editing, mouse selection, copy-on-select, fullscreen images, and remaining dock/cursor styling are still open.
- **Fullscreen scroll styling** (`fullscreen-scroll`, `fullscreen-indicator-light-custom-key`): Home/End and the configured jump key reach the same content as pi. At the top, Bend resets the background around the scrollbar on a user-message row differently; in the light theme, scrollbar colors also differ. The indicator badge itself matches.
- **Fullscreen exit styling** (`fullscreen-exit`, `fullscreen-turn-exit`): the final visible transcript, dock, and resume hint now match pi in both cases. Bend still paints the blank editor row with an inverse cursor; an untouched exit also uses the active-theme border color where pi uses its initial border color.
- **Settings panel coverage** (`settings`): the native panel has 25 rows where pi has 31 in the test terminal. HTTP idle timeout, warnings, TUI mode, fullscreen exit output, fullscreen scrollbar and fullscreen copy-on-select controls are missing. The auto-compaction footer marker now updates correctly when the setting changes.
- **Marked thinking picker position** (`settings-model-thinking-marked`): the thinking-level panel retains one extra blank row before the header after opening from a model with a saved override. Regular-mode document clipping has been removed; the scoped-model picker and other thinking-settings scenarios now match plain screen content. This marked case still needs its preceding model-panel height checked.
- **Loaded theme startup notices** (`settings-theme-marked`, `settings-theme-custom-name`): Bend omits the startup `[Themes]` resource section. That also changes how much header content scrolls offscreen when opening the theme picker.
- **Model picker ANSI row resets** (`hotkeys-custom-binding`, `model-selector-all-filter`, `scoped-models-selector`, `scoped-models-controls`): the configured model-select key works and plain screen content matches. The native main-screen renderer places a few ANSI resets at the starts of following rows instead of at the ends of the preceding rows.
- **Resumed large session startup latency** (`large-session-typing`): the terminal capture now matches after moving restored messages behind tool setup. Reaching the editor after the resume prompt was still about six times slower than pi in the measured run; individual keystrokes painted at similar speed.
- **RPC command ordering around a prompt** (`steer-and-queue`): Node runs a
  prompt's microtasks up to its first awaited I/O before reading the next
  stdin line, so a steer sent right after the prompt response arrives while
  the model streams. Bend's RPC reader waits for the prompt's user message
  (the loop has then polled the steering queue) or the prompt's end. When a
  prompt first compacts, pi reads the next command during the compaction
  request instead; Bend still waits for the user message.
