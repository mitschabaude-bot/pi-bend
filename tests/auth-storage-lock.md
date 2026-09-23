# Auth-storage transactions

The file backend now holds a native interprocess lease across each reload, modification callback and deletion. The shared `runtime/file-lock.bend` protocol interoperates with proper-lockfile. Auth uses a 30-second stale/acquisition interval, 15-second heartbeat, and exponential rounded jitter capped at two seconds. Retry sleeps are cancellable. In-memory storage retains the same callback contract without a filesystem lease.

Cancellation and lease ownership are checked before the callback, immediately before writing and on completion. Release always joins the heartbeat worker. Failed callbacks retain their primary error; release failures are also reported. A compromised owner cannot write a refreshed credential or remove the replacement lock. The whole document is re-read while locked, so updating one provider preserves other processes' changes. Reads without a signal still fall back to the last valid snapshot on reload failure; reads supplied with a signal propagate errors.

Unlike upstream's check-then-create before locking, this implementation creates the auth file only when committing data under the lease, avoiding a first-write overwrite race. Newly created auth files retain the existing 0600 mode. Parent-directory creation still uses the existing filesystem API; enforcing upstream's 0700 mode on new parent directories remains pending. The revision cache/coalesced reload optimization, full OAuth-refresh orchestration cases, and complete upstream auth-storage suite also remain pending. The separate read-only credential helper remains read-only and does not acquire a write lease.

The existing auth-storage/runtime-credentials checks pass on Bun and native one/four workers. New tests preserve all **24 mixed Node/Bend updates**, reject writes after cancellation during a callback (including a no-change callback), interrupt a lock wait, detect replacement mtime before committing, preserve malformed files and retire leases after errors. Pre-aborted operations do not create missing parent directories. These storage tests use temporary fake credentials only. Separately, the rebuilt native CLI passed smoke checks and a live request through the existing Codex OAuth login. The Node oracle is actual proper-lockfile 4.1.2, not a Python locking implementation.

```sh
build/bend-process-files/bend2/main.ts tests/auth-storage.bend -o build/auth-storage.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/auth-storage.bend build/auth-storage
build/bend-process-files/bend2/main.ts tests/auth-storage-lock.bend -o build/auth-storage-lock.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/auth-storage-lock.bend build/auth-storage-lock
python3 tests/auth_storage_check.py
python3 tests/auth_storage_lock_check.py --proper-lockfile /path/to/proper-lockfile-4.1.2
```
