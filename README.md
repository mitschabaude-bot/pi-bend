# pi-bend

A native Bend port of [pi](https://github.com/earendil-works/pi), pinned to revision `46c9de402` (0.85.1). The full modular port is **in progress**. The executable under `src/` is still a bootstrap prototype; it is not the finished library-based CLI.

The target is pi's functionality, public abstractions and terminal behavior, with its complex dependencies implemented in pure Bend. Small OS effects provide system calls; networking protocols, cryptography, parsing and application behavior live in Bend. Extensions will use Bend; JavaScript/TypeScript extension compatibility is excluded. Immutable values, structural equality and explicit errors replace incidental JavaScript object semantics. See [architecture](docs/architecture.md) and [native semantics](docs/native-bend.md).

## Working today

The modular OpenAI Responses provider runs over native DNS, TLS 1.3, certificate validation, HTTP and SSE. It connects to the library agent loop and public read, write, edit and Bash tools. A live native subagent authored a glob-matching feature, applied review feedback, and completed verification on Bun and native one/four threads. [Provenance and validation](tests/glob.md) distinguish this milestone from full port completion.

The coding-agent libraries also include CLI argument parsing, typed messages, [session context reconstruction](tests/session-context.md) and [immutable session state](tests/session-state.md), system-prompt construction and [project-context loading](tests/project-context.md), Bash execution, prompt template loading and expansion, and native image handling. Native [skill discovery](tests/skills.md) includes filesystem metadata, frontmatter parsing, Unicode-aware ignore rules, deduplication and collision diagnostics. The [ls tool](tests/ls-public.md) has native execution with explicit ordering; its default collation policy remains pending. Component records describe exact scope and approved differences: [CLI arguments](tests/cli-args.md), [system prompts](tests/system-prompt.md), [prompt templates](tests/prompt-templates.md), [directory metadata](tests/filesystem-directory.md), and [ignore matching](tests/ignore.md).

The modular CLI now supports noninteractive text and JSON output through the native libraries, with OpenAI API-key authentication, stored Codex OAuth credentials, and read/write/edit/Bash tools; see [CLI validation](tests/print-cli.md). Remaining work includes complete CLI modes, session management and persistence, complete OAuth flows, complete provider coverage, resource-loading integration, native extensions, and terminal/editor parity. Passing the native subagent milestone does not establish those requirements. The prototype's libcurl/ICU adapters remain migration liabilities and are not dependencies of the pure library build.

## Build and validation

Native library builds use the patched Bend toolchain, Bun to run its compiler, and Clang. The resulting native programs do not need a JavaScript runtime. Python and test-only TypeScript/JavaScript references provide differential and IO checks; they do not implement production functionality.

The required toolchain patches and their evidence are in [patches/README.md](patches/README.md), with component-specific additions described beside their tests. Set `BEND` to the patched `bend2/main.ts` for your checkout. `scripts/build-pure.sh` defaults to Clang `-O1`; `PI_BEND_OPT` overrides optimization and `BEND_TUS` selects parallel translation units.

For example, with that toolchain configured:

```sh
BEND_TUS=8 sh scripts/build-pure.sh tests/glob-agent.bend build/glob-agent
python3 tests/glob_check.py build/glob-agent --threads 1
python3 scripts/test-inventory.py
python3 scripts/check-proofs.py
```

Build and run the modular print CLI with an OpenAI API key already configured in the environment or pi authentication storage:

```sh
BEND_TUS=8 sh scripts/build-pure.sh packages/coding-agent/src/main.bend build/pi-cli
./build/pi-cli -- --model gpt-4.1-mini -p "Summarize this directory"
```

The first `--` passes the remaining arguments through Bend's runtime to pi. Interactive mode and session persistence are still pending.

The legacy `scripts/setup.sh`, `scripts/build.sh` and `scripts/test.sh` target the bootstrap executable and require libcurl/ICU development libraries. They are not the acceptance gate for the modular port. Credentials and private sessions must stay outside the repository.

Generic contracts and machine-checked proofs live in [LAWS.bend](LAWS.bend) and [PROOF.bend](PROOF.bend). Differential, integration, concurrency and performance checks complement those proofs. The [source-hashed upstream inventory](tests/upstream-inventory.json) records each suite as pending, partial or ported; successful demonstrations and test counts do not imply complete parity.

Bend bugs and performance problems are investigated in [the issue log](docs/bend-issues.md). Missing primitives are implemented here, with design and validation records alongside their code. Agents coordinate ownership and handoffs in [AGENT-LOG.md](AGENT-LOG.md).
