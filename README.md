# pi-bend

**A coding agent written in [Bend](https://bend-lang.com).** A native port of [pi](https://github.com/earendil-works/pi), from its interactive terminal and modular agent libraries down to HTTP, TLS, cryptography and Unicode.

Building pi-bend also meant building out Bend: adding missing libraries and OS primitives, and scaling the compiler to handle a full application. Networking, parsing, cryptography and rendering run in Bend, with small OS effects for system calls.

Watch pi-bend edit a file, delegate tests to another native pi-bend agent, and run them. Shown at 2× speed.

https://github.com/user-attachments/assets/6c637f1c-0065-4cae-b951-94f1e064306a

The port targets pi v0.87.1 (`f07218c4d`); full parity is still in progress. Extensions are native Bend, with immutable values and explicit updates in place of JavaScript object semantics. See the [architecture](docs/architecture.md) and [scope decisions](docs/scope-decisions.md).

## Finished Components

The port includes the application, reusable Bend libraries and the compiler/runtime support needed to run them. This is an inventory of implemented components, not a claim of complete upstream parity; remaining gaps are tracked through the [source coverage reviews](docs/source-coverage.md) and [test inventory](tests/UPSTREAM.md).

| Layer | Component | Built here |
| --- | --- | --- |
| Application | [Interactive terminal](packages/coding-agent/src/modes/interactive/) | Streaming answers and tool output, editor and history, model/thinking selection, themes, settings, cancellation, queued prompts and fullscreen mouse selection. |
| Application | [Print and RPC modes](packages/coding-agent/src/modes/) | Text/JSON output and a JSONL RPC interface for driving agent sessions. |
| Application | [Coding tools](packages/coding-agent/src/core/tools/) | Read, write, edit, Bash, grep, find and ls; diffs, output truncation and terminal previews. |
| Application | [Sessions and context](packages/coding-agent/src/core/) | JSONL persistence, resume/search, tree navigation, forks, import/export, sharing, compaction, system prompts, project instructions, skills and prompt templates. |
| Application | [Native extensions](packages/coding-agent/src/core/extensions/) | Bend commands, tools, hooks, renderers, prompts and widgets; a linked [subagent extension](packages/coding-agent/src/extensions/). |
| Agent library | [Agent loop](packages/agent/src/) | Typed messages and events, streamed model requests, tool execution, hooks, queues, cancellation and immutable event snapshots. |
| AI library | [Provider APIs](packages/ai/src/api/) | OpenAI Responses/Codex and Completions, Azure, Anthropic, Google GenAI/Vertex, Mistral, Bedrock and pi-messages, with model catalogs and compatible provider routing. |
| AI library | [Authentication](packages/ai/src/auth/) | Credential storage and refresh; browser/device OAuth flows for Codex, Anthropic, Copilot, Radius, Kimi, xAI, OpenRouter and Meta. |
| AI library | [Cloud credentials](packages/ai/src/api/) | AWS credential resolution and SigV4; Google Application Default Credentials, token exchange and service-account signing. |
| Terminal library | [TUI](packages/tui/src/) | Terminal input and rendering, components, layouts, editor, fullscreen mode and mouse handling. |
| Terminal library | [Markdown and LaTeX](packages/tui/src/components/markdown.bend) | GFM terminal rendering, tables, code blocks and [math rendering](packages/tui/src/latex.bend). |
| Networking | [DNS](packages/runtime/src/dns-resolver.bend) | Wire codec, resolver configuration, hosts files, UDP transport, IPv4/IPv6 addressing and interface scopes. |
| Networking | [HTTP and fetch](packages/runtime/src/fetch.bend) | Request/response codecs, streaming bodies, connections, proxy handling and cancellation. |
| Networking | [SSE](packages/runtime/src/sse.bend) and [WebSocket](packages/runtime/src/websocket.bend) | Incremental event decoding, WebSocket framing and client transport. |
| Networking | [TLS 1.3](packages/runtime/src/tls13-client.bend) | Handshake, key derivation, encrypted records, X.509 certificate-chain validation and trust loading. |
| Cryptography | [Hashes and key derivation](packages/runtime/src/) | SHA-256/512, HMAC, HKDF and SHA-1 for protocol/cache uses. |
| Cryptography | [Ciphers and signatures](packages/runtime/src/) | AES-128-GCM, X25519, ECDSA, RSA signing/verification, big integers and modular/prime-field arithmetic. |
| Data | [JSON and schemas](packages/runtime/src/schema.bend) | JSON parsing/serialization, partial streaming JSON, schema validation and immutable records. |
| Data | [Text formats](packages/runtime/src/) | YAML, URL/URI encoding, IDNA/Punycode, Base64, PEM, DER, semver and hosted Git URLs. |
| Data | [Markdown lexer](packages/runtime/src/marked/) | A Bend port of marked's GFM lexer, tokenizers and extension hooks. |
| Data | [Syntax highlighting](packages/runtime/src/highlight.bend) | A highlight.js lexer with generated language grammars over the native ECMAScript regex engine. |
| Text | [Regular expressions](packages/runtime/src/ecma-regex.bend) | ECMAScript regex parsing and execution, shared by parsers, highlighting and search. |
| Text | [Unicode](packages/runtime/src/) | UTF-8/UTF-16, case mapping/folding, grapheme and word boundaries, CJK/SEA segmentation and collation. |
| Files | [Paths and search](packages/runtime/src/) | POSIX paths, glob/minimatch, ignore rules, directory traversal and file search. |
| Media | [Images](packages/runtime/src/image.bend) | PNG, JPEG, GIF, BMP and WebP decoding, resizing and image encoding. |
| Media | [Compression and framing](packages/runtime/src/) | DEFLATE, CRC-32 and AWS event-stream encoding/decoding. |
| Foundations | [Collections and values](packages/runtime/src/) | Persistent records/maps, queues, stable sorting, strings, numeric conversion and date/time helpers. |
| Foundations | [Async resources](packages/runtime/src/) | Callbacks, deferred values, cancellation, deadlines, concurrent operations and resource ownership. |
| OS primitives | [Sockets](patches/README.md) | TCP/UDP, cancellable connect, byte I/O, readiness, shutdown and network-interface lookup. |
| OS primitives | [Files and processes](patches/README.md) | Filesystem metadata and byte I/O, temporary files, permissions, child processes, pipes, signals and exit status. |
| OS primitives | [Terminal, time and environment](patches/README.md) | Terminal acquisition/restoration and dimensions, cancellable timers, clocks, entropy, environment and system identity. |
| Toolchain | [Compiler and runtime patches](patches/README.md) | Shared imports, specialization and layout reuse, emission worklists, large-program limits, native scalar/string operations and compiler memory/performance fixes. |
| Toolchain | [Incremental native builds](docs/incremental-build.md) | Stable generated identities and translation-unit object reuse between builds. |

The libraries above are implemented in Bend. The OS primitives are small effects at the system-call boundary; Bun runs the compiler, while the resulting native executable needs no JavaScript runtime.

## Build and validation

Native library builds use the patched Bend toolchain, Bun to run its compiler, and Clang. The resulting native programs do not need a JavaScript runtime. Python and test-only TypeScript/JavaScript references provide differential and IO checks; they do not implement production functionality.

The required toolchain patches and their evidence are in [patches/README.md](patches/README.md). The shared `build/bend-native-toolchain/bend2` already includes the platform identity and callback socket effects. `scripts/build-pure.sh` uses that toolchain by default and Clang `-O1`; `PI_BEND_OPT` overrides optimization and `BEND_TUS` selects parallel translation units.

For example, with that toolchain configured:

Canonical library tests currently use Bend 2.0.7 with the explicit [compiler patches](patches/README.md) for shared imports, channel identity and exact monotonic clock ticks. `scripts/build-pure.sh` honours `PI_BEND_OPT` (Clang optimisation, `-O1` by default; `-O0` for development iterations) and `BEND_TUS` (compile the generated C as that many translation units in parallel; the compiler reads the same variable when it emits).
```sh
BEND_TUS=8 sh scripts/build-pure.sh tests/glob-agent.bend build/glob-agent
python3 tests/glob_check.py build/glob-agent --threads 1
python3 scripts/test-inventory.py
python3 scripts/check-proofs.py
```

Build and run the modular CLI with an OpenAI API key already configured in the environment or pi authentication storage:

A cold build takes about 3.5 minutes (about 2.2 minutes of Bend emission, then Clang at `-O1`) and emission peaks at about 16 GB, because Bun sizes its heap to the machine's memory; on a smaller machine, `BUN_JSC_forceRAMSize=16000000000` lowers the peak for a few percent more emission time. `scripts/build-cli.sh` builds [incrementally](docs/incremental-build.md): it compiles only the translation units whose C changed, from an object cache shared by all worktrees, so a small edit rebuilds in about 2.5 minutes (`BEND_INCREMENTAL=0` for the ordinary build). For correctness checks, `PI_BEND_OPT=-O0` makes Clang faster still; the binary runs 3-5x slower, so measure timings on `-O1` builds. Builds go one at a time through `flock /tmp/pi-bend-build.lock`.

```sh
sh scripts/build-cli.sh build/pi-cli
./build/pi-cli --model gpt-4.1-mini -p "Summarize this directory"
./build/pi-cli --model gpt-4.1-mini
python3 tests/interactive_run_check.py
printf '%s\n' '{"id":"state","type":"get_messages"}' | ./build/pi-cli --mode rpc
python3 tests/rpc_cli_check.py
./build/pi-cli --export path/to/session.jsonl exported.html
python3 tests/export_cli_check.py
```

The CLI owns its whole command line, as pi does; `BEND_THREADS=N` sets the native worker count. The interactive check runs on one and four native threads from a separate project directory and verifies terminal restoration.

Credentials and private sessions must stay outside the repository.

Generic contracts and machine-checked proofs live in [LAWS.bend](LAWS.bend) and [PROOF.bend](PROOF.bend). Differential, integration, concurrency and performance checks complement those proofs. [Scope decisions](docs/scope-decisions.md) record what the port leaves out or changes. The [source-hashed upstream inventory](tests/upstream-inventory.json) records each suite as pending, partial or ported; successful demonstrations and test counts do not imply complete parity.

The [reviewed upstream source coverage](docs/source-coverage.md) records known implementation gaps; the test inventory records upstream assertion coverage. `python3 scripts/test-inventory.py` checks both records against the pinned source tree.

Bend bugs and performance problems are investigated in [the issue log](docs/bend-issues.md). Missing primitives are implemented here, with design and validation records alongside their code. Agents coordinate ownership and handoffs in [AGENT-LOG.md](AGENT-LOG.md).
