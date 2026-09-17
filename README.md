# pi-bend

Native Bend port of pi, based on `earendil-works/pi` revision `46c9de402` (0.85.1). Work in progress; this is not yet a feature-complete replacement.

Application logic lives in Bend. Native C effects provide operating-system and library interfaces. JavaScript/TypeScript extension compatibility is intentionally excluded; extensions will use Bend.

See [docs/parity.md](docs/parity.md) for the implementation and validation status. Credentials remain in the existing private `~/.pi/agent/auth.json`; never copy credentials into this repository.

## Build and test

Requires Bend 2.0.4, Bun for the Bend compiler, Clang, Python 3 for build/test scripts, and libcurl. The resulting executable uses no JavaScript runtime.

```sh
sh scripts/setup.sh
sh scripts/build.sh
build/pi-bend --no-session -p 'Read this project and explain it'
sh scripts/test.sh
sh scripts/build.sh tests/tool_runner.bend build/test-tools
python3 tests/tools_test.py
```

Current implementation: native print-mode agent loop with OpenAI Codex OAuth, streaming responses, read/write/exact-edit/bash tools. Session persistence, interactive terminal parity, additional providers, and Bend extensions are still in progress. The initial tool implementations are tested but do not yet match every upstream edge case.
