# Modular native print CLI

`packages/coding-agent/src/main.bend` connects native argument parsing, authentication storage, model resolution, system prompts, the agent loop and public tools to text/JSON print modes. It uses the native DNS/TLS/HTTP/SSE provider; prototype libcurl/ICU adapters are not linked. The merged CLI retains the canonical system-prompt implementation, including skill formatting. Resource discovery still needs wiring into this entry point.

```sh
BEND=/path/to/patched/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh packages/coding-agent/src/main.bend build/pi-cli
python3 tests/print_cli_check.py
PI_BEND_LIVE=1 python3 tests/print_cli_check.py
```

The live lane requires `OPENAI_API_KEY` from the environment. Tests never print or commit its value. They verify actual text output, piped prompts, JSON session headers and event order, snapshot-free streaming events, final assistant messages, rejected-request exits, and a temporary-directory write/read task executed by the model through the CLI tool registry. The smoke lane compares help/version against the pinned upstream source and checks malformed options and missing files. These checks establish the implemented print path, not complete CLI parity.

`tests/auth_storage_check.py` and `tests/config_value_check.py` exercise the real storage/configuration modules on Bun and native one/four workers. Shell-command resolution runs only on native backends because the Bun process primitive is unavailable. Existing system-prompt comparisons and the generic-law checker also pass after integration. File storage has no cross-process lock yet; cancellation, all OAuth flows, remaining providers, session persistence, interactive/RPC modes, resource/extension wiring and signal handling remain incomplete. Generated model catalogs are a separate parity limitation.

The private integration compiler includes the directory effects plus `bend-is-terminal.patch` and `bend-halt-silent.patch`. The executable must receive an initial `--` to separate Bend runtime flags from pi arguments. No installed compiler or global pi executable is replaced by these checks.
