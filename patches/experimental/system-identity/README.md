# Native platform identity

`IO.system_identity()` returns a right-associated `(platform, release, arch)` tuple through Bend's existing errno/string result. The native effect reads one `struct utsname` with `uname(2)`; the Bun effect uses Node's `os.platform()`, `os.release()` and `os.arch()`. Native platform and architecture names are mapped to their Node spellings, and an unknown mapping returns `ENOTSUP` rather than emitting an invented User-Agent. No shell, environment variable, application C, or application JavaScript is involved.

The patch adds one Base declaration and two compiler effect files. `scripts/prepare-system-identity-candidate.py` copies a baseline compiler and verifies that every existing file stays byte-identical, with only the declaration appended to Base. The application formats pi-mono's pinned `pi (${nodeOs.platform()} ${nodeOs.release()}; ${nodeOs.arch()})` in pure Bend. Google uses it as the default request header; model and caller headers can still override it. OpenAI's existing provider defaults receive it at AgentRuntime creation. Linux x64 on Bun and native one/four threads is tested; other architecture mappings are source-reviewed but not exercised here.

Ten alternating-order Bun compilations of the unrelated `tests/hostname-control.bend` fixture produced byte-identical JavaScript; generated C is byte-identical too. Median baseline/candidate wall time was 0.14/0.14 seconds and peak RSS was 82,046/80,766 KiB on this shared host. The effect itself makes one `uname` call per Google request and one at AgentRuntime initialization for OpenAI; there is no extra operation in unrelated programs.

```sh
python3 scripts/prepare-system-identity-candidate.py /tmp/bend-system-identity --base /tmp/pi-bend-theme-controller/build/theme-toolchain/bend2
python3 tests/system_identity_check.py --toolchain /tmp/bend-system-identity/main.ts
python3 tests/google_client_loopback.py --toolchain /tmp/bend-system-identity/main.ts --backend all
```
