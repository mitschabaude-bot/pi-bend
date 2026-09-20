# OS interface-index primitive

`IO.interface_index(name)` returns a nonzero OS network-interface index or the existing typed `(errno, message)` failure. Embedded NUL is rejected with EINVAL before an OS call. Native C calls `if_nametoindex` and captures errno before freeing the input buffer. A zero result without errno becomes EIO. No scheduler, resource table or compiler code changes.

The Bun effect lazily binds only `if_nametoindex` and the thread-local errno accessor through Bun's existing FFI facility. It resets and reads errno through a borrowed view, with no allocation or async boundary between lookup and reading the result. Its one library handle is cached for process lifetime. This is a Linux/glibc binding (`libc.so.6`); other Bun platforms return ENOSYS. Native code uses POSIX interfaces; only Linux is tested. The existing Bun runtime already uses libc FFI for its OS effects and error strings. Resolver grammar, address classification, numeric fallback and diagnostics remain pure Bend.

Prepare an isolated candidate, preserving all existing compiler files byte-for-byte except the additive Base declarations:

```sh
python3 scripts/prepare-interface-index-candidate.py build/bend-interface-index-candidate --base build/bend-hostname-candidate
python3 tests/interface_index_check.py
```

Use a fresh destination. No installation is changed. Tests compare live interface results against the host OS, inject values/errors without modifying interfaces, verify UTF-8 names and NUL rejection, repeat successful/failed calls, and exercise live scope-to-endpoint conversion. Two unrelated compile controls compare native/JS output and alternating-order time/RSS samples. These controls do not establish universal performance or portability.

`network-interface.bend` converts primitive failures to a native data record. `resolver-interface.bend` supplies that source to the separately tested scope policy. The application layer does not call FFI or parse host-language objects.
