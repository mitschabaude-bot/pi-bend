# pi-bend

A native Bend port of [pi](https://github.com/earendil-works/pi), targeting v0.87.1 (`f07218c4d`). The full modular port is **in progress**. The executable under `src/` is an older bootstrap prototype; the library-based CLI is `packages/coding-agent/src/main.bend`.

The target is pi's functionality, public abstractions and terminal behavior, with its complex dependencies implemented in pure Bend. Small OS effects provide system calls; networking protocols, cryptography, parsing and application behavior live in Bend. Extensions will use Bend; JavaScript/TypeScript extension compatibility is excluded. Immutable values, structural equality and explicit errors replace incidental JavaScript object semantics. See [architecture](docs/architecture.md) and [native semantics](docs/native-bend.md).

## Working today

The modular OpenAI Responses provider runs over native DNS, TLS 1.3, certificate validation, HTTP and SSE. It connects to the library agent loop and public read, write, edit and Bash tools. A live native subagent authored a glob-matching feature, applied review feedback, and completed verification on Bun and native one/four threads. Native Anthropic Messages and Google Generative AI providers are registered too. Local HTTP/SSE checks cover their response, error and tool-result paths, Anthropic OAuth refresh, and Google signed thinking replay and retries; neither provider has a verified live service request yet. [Provenance and validation](tests/glob.md) distinguish these milestones from full port completion.

The coding-agent libraries also include CLI argument parsing, typed messages, [session context reconstruction](tests/session-context.md) and [immutable session state](tests/session-state.md), system-prompt construction and [project-context loading](tests/project-context.md), Bash execution, prompt template loading and expansion, and native image handling. Native [skill discovery](tests/skills.md) includes filesystem metadata, frontmatter parsing, Unicode-aware ignore rules, deduplication and collision diagnostics. The [ls tool](tests/ls-public.md) has native execution with explicit ordering; its default collation policy remains pending. Component records describe exact scope and approved differences: [CLI arguments](tests/cli-args.md), [system prompts](tests/system-prompt.md), [prompt templates](tests/prompt-templates.md), [directory metadata](tests/filesystem-directory.md), and [ignore matching](tests/ignore.md).

The modular CLI supports noninteractive text/JSON output, an interactive terminal loop, a native JSONL RPC endpoint, auth-filtered model listing and scoped model cycling, a `--resume` session picker, and standalone HTML session export, with OpenAI API-key authentication, stored Codex OAuth credentials, session persistence, and read/write/edit/Bash tools; see [CLI validation](tests/print-cli.md). Interactive mode opens with no credentials or model, so `/login` is available on a fresh installation; prompts report the missing model until one is selected. Interactive `/login` supports OpenAI Codex device authorization and Anthropic PKCE, including a localhost browser callback and manual code or redirect-URL fallback when the callback port is occupied or inaccessible. Interactive `/logout` lists stored credentials, removes the chosen OAuth or API-key entry, and refreshes available models in the same session. The interactive loop mounts the editor, streams messages and tool calls, restores saved tool results, updates its footer from session events, switches light/dark themes with terminal color notifications, and restores the terminal on exit. Its worker handles `/thinking` and `/compact` without blocking input; Escape aborts an active response and restores queued steering, Alt+Enter queues a follow-up, Alt+Up restores queued input, and double Ctrl+C exits. `/model` can select an available model; further interactive command and terminal parity remain unfinished. Live native runs received OpenAI and Codex answers and executed Bash; one long-lived RPC process handled two model turns and retained their context. RPC exposes typed state, queue, thinking and model controls, session-tree reads, session statistics, and lazy HTML export; command coverage remains incomplete. Remaining work includes interactive command and terminal parity, complete provider coverage, resource-loading integration and native extensions. The prototype's libcurl/ICU adapters remain migration liabilities and are not dependencies of the pure library build.

## Build and validation

Native library builds use the patched Bend toolchain, Bun to run its compiler, and Clang. The resulting native programs do not need a JavaScript runtime. Python and test-only TypeScript/JavaScript references provide differential and IO checks; they do not implement production functionality.

The required toolchain patches and their evidence are in [patches/README.md](patches/README.md). The shared `build/bend-native-toolchain/bend2` already includes the platform identity and callback socket effects. `scripts/build-pure.sh` uses that toolchain by default and Clang `-O1`; `PI_BEND_OPT` overrides optimization and `BEND_TUS` selects parallel translation units.

For example, with that toolchain configured:

Canonical library tests currently use Bend 2.0.7 with the explicit [compiler patches](patches/README.md) for shared imports, channel identity and exact monotonic clock ticks. Their pure build path does not link the bootstrap's libcurl/ICU adapters. `scripts/build-pure.sh` honours `PI_BEND_OPT` (Clang optimisation, `-O1` by default; `-O0` for development iterations) and `BEND_TUS` (compile the generated C as that many translation units in parallel; the compiler reads the same variable when it emits).
```sh
BEND_TUS=8 sh scripts/build-pure.sh tests/glob-agent.bend build/glob-agent
python3 tests/glob_check.py build/glob-agent --threads 1
python3 scripts/test-inventory.py
python3 scripts/check-proofs.py
```

Build and run the modular CLI with an OpenAI API key already configured in the environment or pi authentication storage:

```sh
BEND_TUS=8 sh scripts/build-pure.sh packages/coding-agent/src/main.bend build/pi-cli
./build/pi-cli -- --model gpt-4.1-mini -p "Summarize this directory"
./build/pi-cli -- --model gpt-4.1-mini
python3 tests/interactive_run_check.py
printf '%s\n' '{"id":"state","type":"get_messages"}' | ./build/pi-cli -- --mode rpc
python3 tests/rpc_cli_check.py
./build/pi-cli -- --export path/to/session.jsonl exported.html
python3 tests/export_cli_check.py
```

The first `--` passes the remaining arguments through Bend's runtime to pi. The interactive check runs on one and four native threads from a separate project directory and verifies terminal restoration.

The legacy `scripts/setup.sh`, `scripts/build.sh` and `scripts/test.sh` target the bootstrap executable and require libcurl/ICU development libraries. They are not the acceptance gate for the modular port. Credentials and private sessions must stay outside the repository.

Generic contracts and machine-checked proofs live in [LAWS.bend](LAWS.bend) and [PROOF.bend](PROOF.bend). Differential, integration, concurrency and performance checks complement those proofs. The [source-hashed upstream inventory](tests/upstream-inventory.json) records each suite as pending, partial or ported; successful demonstrations and test counts do not imply complete parity.

Bend bugs and performance problems are investigated in [the issue log](docs/bend-issues.md). Missing primitives are implemented here, with design and validation records alongside their code. Agents coordinate ownership and handoffs in [AGENT-LOG.md](AGENT-LOG.md).
