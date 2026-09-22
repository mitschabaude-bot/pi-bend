# Native interprocess file locking

`runtime/file-lock.bend` implements the directory/mtime protocol used by pinned **proper-lockfile 4.1.2**. SettingsManager and auth storage can lock the same `<canonical file>.lock` directory as existing Pi processes. Exclusive `mkdir`, directory mtime, heartbeat updates, stale reclamation and `rmdir` release remain interoperable; this does not substitute `flock` or run a host locking library in production.

## Owned API

- `defaults()` gives `Options{10000,5000,1n,20,True{}}`: stale milliseconds, heartbeat milliseconds, acquisition attempts, retry milliseconds, and realpath resolution. Settings uses `Options{10000,5000,10n,20,False{}}`, matching its ten fixed attempts with 20 ms between `ELOCKED` responses.
- `acquire(path,options,signal:Maybe<AbortSignal<Unit>>)` returns an affine `Owner` or typed error. Retry sleeps are cancellable, and cancellation after acquiring a directory cleans it up before returning. A concurrent substantive IO/cleanup failure is retained rather than hidden by cancellation.
- `borrow(owner)` returns the owner and a `Handle`; `check(handle)` performs a fresh serialized ownership check, making it suitable both before and after protected writes. It returns a sticky compromise once ownership is lost.
- `release(owner)` cancels and joins the heartbeat worker, retires its synchronization resources, verifies ownership, and then removes the directory. Callers finish all borrowed-handle operations before release. Every transaction path must release its owner, retaining both an operation failure and a release failure when both occur.

The single heartbeat worker compares the observed mtime with the lease's last mtime before updating. Missing or changed directories compromise the lease. Other stat/utimes failures retry after one second until the stale threshold is exceeded; successful updates can recover after a long pause if the mtime still belongs to this lease, matching the reference policy. Acquisition removes a stale directory at most once per attempt before retrying exclusive creation. The module contains one explicitly unbounded, owner-cancelled IO loop and no host-language lock/retry/heartbeat policy.

## Timestamp precision and minimal effects

`patches/bend-file-lock-effects.patch` adds four POSIX filesystem effects, with corresponding hosted implementations: `Directory.create`, `Directory.remove`, `File.modified_time`, and `File.set_times_milliseconds`. It changes no compiler or existing effect implementation. The tested private toolchain is `build/bend-lock-toolchain/bend2/main.ts`; the patch has not been globally installed.

`File.modified_time` returns signed Unix seconds as high/low words plus exact nanoseconds. Native uses `stat`; hosted uses bigint `statSync`. `File.set_times_milliseconds` accepts a signed high/low millisecond pair and sets both atime and mtime using `utimensat`/`utimesSync`. It rejects embedded NUL paths and timestamps outside ±8,640,000,000,000,000 ms, the shared representable Date range, instead of silently narrowing them. Actual filesystem timestamp range/precision remains observable through stat.

Protocol rounding stays in Bend. Node constructs `Stats.mtime` by rounding milliseconds; experimentally, Node `utimes(Date)` can write a timestamp just below the requested millisecond even though `stat.mtime.getTime()` reports that millisecond. Flooring raw nanoseconds would falsely report compromise. The native policy reproduces the reference's rounded Date comparison and probes each new lease with `ceil(now/1000)*1000+5` to distinguish second precision. Unlike the reference's process-global precision cache, each lease probes its actual directory, so different mounts do not inherit an unrelated filesystem's precision.

## Behavior choices and scope

Invalid options are rejected: at least one attempt, stale interval at least 2,000 ms, and heartbeat between 1,000 ms and half the stale interval. The reference silently clamps several invalid inputs. Pre-aborted acquisition returns before path resolution or directory creation. Cancellation and release are explicit owned operations rather than exceptions and a process-global registry. Release additionally checks the mtime before removing the directory, so an already-lost owner does not delete a replacement owner's lock merely because its next heartbeat has not run yet. Compromise and paired cleanup failures remain typed errors rather than being ignored or thrown from a detached callback.

The protocol is cooperative and shares proper-lockfile's stat/update and stale-removal race limits; this is not an atomic compare-and-remove filesystem operation. The implementation covers the default `.lock` path protocol and fixed retry policy needed by settings; custom lock paths, user-supplied filesystem adapters and the reference's global exit/signal cleanup hooks are not ported. Normally scoped owners release before return. Abrupt process death, or exiting without releasing an owner, leaves a directory for stale recovery. Auth storage can implement its separate deadline/jitter retry policy around single-attempt acquisition without changing this protocol.

## Evidence

The committed harness launches actual Node proper-lockfile 4.1.2 processes beside the compiled Bend implementation. It checks both heartbeat directions beyond the stale timeout, Node/Bend crash recovery, fixed retries, prompt cancellation of a five-second wait, realpath versus literal-symlink paths, relative paths, missing/nonempty locks, sticky compromise, replacement-owner preservation, thirty simultaneous mixed-process read/modify/write increments, and 100 acquire/release cycles without descriptor growth. Exact signed/submillisecond metadata, overflow rejection and NUL rejection are included. No credentials or external network endpoints are used.

The final source passes **34 checks on Bun and 46 checks each on O1 native `--threads 1` and `--threads 4`**. Each backend also performs the thirty mixed-process increments and 100 retirement cycles described above.

Native fault injection adds initial probe failures, retained primary plus cleanup failures, release failure, transient and permanent heartbeat stat/utimes errors, second-precision filesystems, a delayed in-flight update, cancellation during precision probing, and concurrent cancellation plus primary/cleanup failures. This is syscall fault injection for lifecycle/error behavior, not negative laws or mutated proofs. Every worker and timer is joined before returning from release/cancel.

```sh
npm install --prefix build/reference --no-save proper-lockfile@4.1.2
build/bend-native-toolchain/bend2/main.ts tests/file-lock.bend -o build/file-lock.js
sh scripts/build-pure.sh tests/file-lock.bend build/file-lock
python3 tests/file_lock_check.py --runner build/file-lock.js --proper-lockfile /path/to/proper-lockfile
python3 tests/file_lock_check.py --runner build/file-lock --threads 1 --proper-lockfile /path/to/proper-lockfile
python3 tests/file_lock_check.py --runner build/file-lock --threads 4 --proper-lockfile /path/to/proper-lockfile
```

The `--proper-lockfile` argument defaults to `build/reference/node_modules/proper-lockfile`. The oracle package is test-only and must be version 4.1.2. The syscall-fault/descriptor harness is Linux-specific; the production effects also contain the standard macOS stat timestamp field selection, which has not been executed here.
