# Interactive session replacement

The mounted interactive mode routes `/new` and `/clear` to `AgentSessionRuntime.newSession`. The host owns teardown and construction. Its rebind hook updates one caller-owned `Ref<AgentSession>`; the controller reads that Ref for each queued command, control action, selection and prompt. The active editor and model picker also read it. The mode callback subscribes the existing UI listener to the replacement session and resets the transcript, footer, notice and draft. The hook is removed before the view and host are disposed.

`interactive_new_run_check.py` mounts a real PTY around a persisted host fixture. It sends a prompt, exports HTML and JSONL, runs `/new`, `/clear`, sends another prompt and exits. It checks the HTML payload, the exported branch, terminal restoration, three distinct session paths, and separate old/new histories. The empty middle session has no file until its first append. Run the same binary with native one and four threads. The mode-boundary callback is injectable; the fixture uses the same API as `main.bend` with a faux provider. This does not claim extension lifecycle events or RPC rebinding.

```sh
BEND=build/bend-native-toolchain/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/interactive-new-run.bend build/interactive-new-run
python3 tests/interactive_new_run_check.py
```
