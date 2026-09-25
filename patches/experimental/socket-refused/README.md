# Connection-refusal classification

`Socket.isConnectionRefused(U32) -> IO(Bool)` classifies a platform socket error without putting errno numbers into Bend resolver policy. The native effect compares against the platform's `ECONNREFUSED`; the Bun effect uses Linux 111 or Darwin 61. It introduces no resource table, scheduler change, or compiler change. The native predicate makes no syscall; Bun uses the existing lazy platform helper. Darwin is implemented but untested.

The constants are grounded in [Linux's generic errno definitions](https://github.com/torvalds/linux/blob/master/include/uapi/asm-generic/errno.h) and [Apple's errno documentation](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/intro.2.html). This primitive classifies an error code, not a DNS response: DNS REFUSED is a separate protocol outcome.

Prepare a fresh isolated candidate, optionally extending the existing DNS primitive candidate:

```sh
python3 scripts/prepare-socket-refused-candidate.py build/bend-dns-refused-candidate --base build/bend-dns-entropy-candidate
python3 tests/socket_refused_classifier_check.py build/bend-dns-refused-candidate build/bend-dns-entropy-candidate
python3 tests/dns_address_search_check.py build/bend-dns-refused-candidate
```

The preparation script verifies byte identity of every pre-existing file and exact append-only Base additions. The classifier checker covers codes 0–511, 65535 and 4294967295 against the host errno definition on native one/four threads and Bun, and verifies identical unrelated C/JS output. Live resolver tests exercise actual IPv4/IPv6 connection refusal, plus search continuation for other transport failures. No installed toolchain change is required.

Compile controls use a refusal-only candidate against the installed baseline, with 20 alternating-order pairs per fixture. They measure loading/checking/C emission, not network throughput or runtime performance; unused-effect generated C must remain identical. Results and source hashes live in the validation record. These measurements cannot establish universal absence of performance regressions.

On this shared Linux host, candidate/baseline median compilation-time ratios were 1.003 for the TCP text fixture and 0.989 for the UTF-8 fixture. Median peak RSS was 152,570 versus 152,254 KiB and 405,692 versus 419,056 KiB respectively. Generated C was identical in all paired samples. These small timing differences do not establish a speedup or a measurable regression.
