# OS entropy primitive

`Entropy.bytes(count)` returns an immutable byte list or an OS error. Requests are bounded to 256 bytes; zero returns an empty list without a syscall, and larger requests fail with `EINVAL` before touching the OS. There is no generator state, descriptor, timer, retry loop or fallback seed. Linux uses `getrandom` with `GRND_NONBLOCK`: entropy initialization cannot park a Bend worker. OS errors propagate, and an unexpected short success becomes `EIO` without exposing partially filled output. The syscall contract and small-read guarantee are described in the [Linux manual](https://man7.org/linux/man-pages/man2/getrandom.2.html).

This is an additive OS effect, not a foreign implementation of a complex dependency. C and Bun effects only call the OS and pack Bend values. No existing compiler, scheduler or effect is edited. Bun resolves the symbol lazily, following the runtime's existing libc FFI convention. Linux is implemented and exercised; nonempty requests on other native platforms return `ENOSYS`. Darwin needs its own OS adapter and real platform validation before this primitive provides cross-platform entropy. The Bun adapter uses the runtime's existing 64-bit libc ABI convention.

Prepare and check an isolated candidate:

```sh
python3 scripts/prepare-entropy-candidate.py build/bend-entropy-candidate
python3 tests/entropy_check.py build/bend-entropy-candidate
python3 scripts/benchmark-tcp-bytes.py build/bend-entropy-candidate build/entropy-performance.json entropy_bytes.c entropy_bytes.js
```

The preparer also accepts `--base` to compose with existing candidates. It checks all existing files remain byte-identical and Base changes only by appending the declaration. Nothing is installed. The existing `/dev/urandom` seed adapter and caller-supplied DNS IDs remain unchanged; wiring this effect into resolver defaults and other entropy consumers is subsequent implementation work.

The regression performs 263 requests per outcome on native one/four threads and Bun. Live Linux output is checked for exact length and byte bounds. Disposable syscall injection checks every byte value, every supported length, repeated calls, oversized arguments, `EAGAIN`, `ENOSYS`, `EINTR`, and two forms of short return. Exact call counts verify zero and oversized requests bypass the syscall. All 5,523 requests pass (789 live, 4,734 injected). These tests do not infer cryptographic quality from sample uniqueness or establish performance on other platforms. No live entropy values are stored in the validation record.

The [validation record](../../../docs/runtime-validation/2026-09-20-entropy.json) retains source hashes, guarded emission observations and compilation controls. Two existing fixtures emit byte-identical C in all 20 alternating baseline/candidate measurement pairs, and byte-identical JavaScript in separate controls. Median candidate/baseline wall-time ratios are 0.988 for the TCP text fixture and 1.004 for UTF-8; median peak RSS is 153,340/151,948 KiB and 409,958/412,308 KiB respectively. These shared-host measurements show no material compilation-time change in the tested workloads, not universal performance neutrality. Existing generated programs are unchanged. The candidate remains uninstalled.
