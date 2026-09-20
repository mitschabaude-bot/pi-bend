# OS hostname primitive

`IO.get_hostname() -> IO(Result<&1, &1, U32 & String, String>)` returns the operating-system hostname, independently of the `HOSTNAME` environment variable. The native effect makes one `uname` call and copies its null-terminated `nodename` into a managed Bend string. It uses the platform's `struct utsname` without a hard-coded buffer size. The Bun effect calls `node:os.hostname`; syscall errors become the existing errno/string result. An unexpected Bun exception without a usable errno maps to EIO. References: [uname](https://man7.org/linux/man-pages/man2/uname.2.html), [Node OS hostname](https://nodejs.org/api/os.html#oshostname).

The addition consists of one Base declaration and two effect files. It changes no compiler, scheduler, resource table or existing effect. Resolver fallback and diagnostics are implemented in Bend. Linux native one/four threads and Bun are tested; Darwin is not tested. This candidate is not installed.

```sh
python3 scripts/prepare-hostname-candidate.py build/bend-hostname-candidate --base build/bend-dns-refused-candidate
python3 tests/hostname_check.py
python3 tests/resolver_hostname_check.py
python3 tests/resolver_system_check.py
```

The preparation script requires a fresh destination and verifies all existing files byte for byte, with an exact append-only Base change. Tests compare the live hostname with the OS, ignore a decoy environment value, and inject empty, dotted, 64-byte and Unicode names and syscall errors. The native shim wraps `uname` only in a test binary; no hostname or UTS namespace is changed. Bun injection modifies only a disposable generated fixture.

Twenty alternating-order compilation pairs for each of two unrelated fixtures retain identical generated C, with identical JS controls too. Median base/candidate times were 0.13/0.13 seconds for the environment-effect control and 0.25/0.25 seconds for the static-sum fixture. Median RSS was 83,926/84,032 KiB and 126,796/127,028 KiB respectively. These scoped, shared-host measurements do not establish universal absence of performance regressions. There is no runtime change in the byte-identical control programs. See the [validation record](../../../docs/runtime-validation/2026-09-20-hostname.json).
