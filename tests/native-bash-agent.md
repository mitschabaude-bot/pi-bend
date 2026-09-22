# Four-tool native model integration

`tests/native-edit-agent.bend` exposes the actual public write, edit, read, and Bash tools through the canonical modular agent loop and native HTTPS Responses provider. The fixture keeps public tool declarations, strict input validation and final model-visible content. Its heterogeneous bridge erases details to Unit only inside this test host; canonical library types remain intact. Bash streaming updates are forwarded into the real loop, and owned tool/update callbacks plus the file mutation queue are disposed after completion.

The existing four model/write/edit/read scenarios remain. Additional native scenarios request a Bash command that checks the edited feature, writes a verification file and returns its contents plus the feature; another returns both stdout and stderr and exits7. The next HTTPS model request must contain the exact successful output or both failure streams and the exit-status message. A Boolean Bash command is rejected before the execution callback runs. The peer verifies filesystem state before responding, all four schemas, original call arguments, matching call/result identifiers, event ordering, callback counts and the final answer. The fixture can also target a live model by supplying a real trust bundle/model/base URL/prompt/cwd and API key, but these tests make only local requests.

Native process effects currently lack a Bun implementation. Hosted runs retain the original four scenarios and Bash schema rejection; actual shell success/failure is tested only on native one/four workers. Shell tests write only inside temporary working directories and invoke real public default operations, with no injected shell implementation.

```sh
BEND=/path/to/combined/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/native-edit-agent.bend build/native-edit-agent
python3 tests/native_edit_agent_check.py native-1
python3 tests/native_edit_agent_check.py native-4
```

The combined toolchain must include filesystem stat/raw-write/regular-file effects and native process/null-stdin effects, including the effect-only multiline entrypoint correction in `patches/bend-process-tu.patch` when compiling multiple translation units. Production source for this fixture includes the owned streaming-output follow-up01cf925. Build and run artifacts remain ignored; no external credentials or model requests are part of these tests.

Validation: the exact fixture passed all seven scenarios on optimized native builds with explicit `--threads 1` and `--threads 4`; the hosted build passed its five supported scenarios. Native Bash success and exit7 both emitted tool-update events, and all test-owned callbacks/tools retired before the final execution-count report. The first eight-unit build exposed duplicate symbols in four compact process effect entrypoints; the isolated effect-only correction was applied before regenerating the successful artifact, without editing generated C or the compiler.
