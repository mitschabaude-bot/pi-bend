# Process identity and local civil time

`patches/bend-process-clock.patch` adds two reusable Base effects, independently of terminal filename policy:

```bend
type LocalTime is Data:
  LocalTime{year: U32, month: U32, day: U32, hour: U32, minute: U32, second: U32}
def Process.id() -> IO(U32)
def Clock.localTime() -> IO(Result<&1,&1,U32 & String,LocalTime>)
```

Month/day are one-based; seconds permit the OS's leap-second value 60. Years outside U32 return EOVERFLOW. Native obtains the current realtime instant and uses `localtime_r` under the host timezone, on existing IO workers so timezone-file loading does not occupy the IO loop. Both clock and conversion failures produce typed errors; a conversion failure without errno becomes EOVERFLOW. Hosted effects use `process.pid` and local Date getters, reject invalid/out-of-range dates, and do no path formatting. This is current local civil time, not a new calendar parser, timezone database or filename API. Platforms retain their own representable date ranges and leap-second conventions.

The patch changes only Base declarations and four new effect files. Existing clock/process functions and compiler code are unchanged. Private candidate: `/home/agent/code/pi-bend-terminal/build/bend-process-clock/bend2/main.ts`, based on the owned-terminal candidate `f0c3474`; the patch also dry-runs independently against that previous candidate. No shared/global compiler installation.

`process_clock_check.py` passes 33 cases under Bun and 38 cases each under optimized native one/four threads, repeated with two translation units. Each case checks four successive calls, exact child PID and duplicated immutable LocalTime values. Coverage includes real current time in UTC, Kiritimati, New York and Kathmandu; seven fixed instants covering pre-epoch time, leap day, spring/fall DST boundaries and local year rollover; negative-year rejection; and native clock/localtime failures, missing errno, and successful recovery after a one-call failure. Python zoneinfo supplies an independent expected civil breakdown. LD_PRELOAD and a hosted Date preload control clocks only in tests.

A one-line C effect entry initially failed root's eight-TU link because the current split-TU tooling did not recognize that function form. Using the standard multiline effect entry fixed the source; the positive fixture now compiles/runs with two TUs, and root's complete terminal fixture compiles with eight. No compiler patch or investigation was needed. Root independently reports 35 real terminal scenarios passing native one/four with these effects, including directory log filenames in three time zones; that terminal policy is outside this primitive handoff.

```sh
patch -p1 -d build/bend-process-clock < patches/bend-process-clock.patch
BEND=build/bend-process-clock/bend2/main.ts sh scripts/build-pure.sh tests/process-clock.bend build/process-clock
BEND=build/bend-process-clock/bend2/main.ts BEND_TUS=2 sh scripts/build-pure.sh tests/process-clock.bend build/process-clock-split
build/bend-process-clock/bend2/main.ts tests/process-clock.bend -o build/process-clock.js
clang -shared -fPIC -O2 tests/process_clock_faults.c -ldl -o build/process-clock-faults.so
python3 tests/process_clock_check.py
```

Apply only to a fresh private copy before running these commands; the validated candidate already has the patch. There is no runtime change to benchmark on existing consumers: these are new opt-in effects, with no compiler-core or allocator changes.
