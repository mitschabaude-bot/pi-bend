# TuiBase render scheduling source comparison

`tests/tui-schedule.bend` drives the production `RenderSchedule` transition definitions with a controlled next-tick queue and timer IDs. `tests/tui_schedule_reference.ts` hash-pins and executes the actual scheduling methods from `pi-mono` revision `46c9de402` under a fake clock, timer queue and `process.nextTick`. Each trace compares requested/immediate flags, active timer, timer allocation, last render time, stop state and ordered side effects. The fake clock advances five milliseconds per explicit action; drawing is stubbed so this isolates scheduling from terminal output and render reentrancy.

All 16 exact traces pass on Bun and optimized native with one/four threads. The comparison covers ordinary request coalescing, 16 ms throttling, forced preemption and cancellation, immediate callback coalescing, `renderNow`, timer and next-tick order, and stopping. `StartRendering` has one known mismatch: upstream `start()` calls `requestRender()` after starting the terminal, so a fresh start queues a schedule callback; the current Bend transition only clears `stopped`. The checker asserts and reports this gap separately. Timer callbacks that invoke a new render request inside `doRender` remain outside this focused trace and need an owner-level callback test.

```sh
/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts tests/tui-schedule.bend -o build/tui-schedule.js
BEND=/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/tui-schedule.bend build/tui-schedule
python3 tests/tui_schedule_check.py
```

This fixture and source oracle are a focused handoff. The private copy of `packages/tui/src/tui-base.bend` is root-owned production code and is excluded from this commit.
