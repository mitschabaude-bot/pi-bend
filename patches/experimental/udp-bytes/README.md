# Binary datagram candidate

Additive `UDP.bind_family`, `UDP.recv_bytes` and `UDP.send_bytes` prototypes. Prepare with `python3 scripts/prepare-udp-candidate.py build/bend-udp-send-candidate --base build/bend-interface-index-candidate`, then run `python3 tests/udp_bytes_check.py build/bend-udp-send-candidate`, `python3 tests/udp_bind_check.py build/bend-udp-send-candidate` and `python3 tests/udp_send_check.py`. They have not been installed.

Binding accepts family 4 or 6 and port 0 through 65,535; zero requests an ephemeral port. IPv6 sockets are IPv6-only, and both families bind wildcard addresses. Sockets are nonblocking and marked close-on-exec. Every setup failure closes the newly allocated descriptor.

The receive endpoint layout matches `Socket.endpoint`: family, four address words, port and scope. A datagram is consumed atomically; the returned byte list is limited to `max`, and the flag indicates discarded excess bytes. Zero-length packets are successful values. The accepted capacity range is 0 through 65,535. Invalid capacity preserves the socket and consumes no packet.

Validated on IPv4 and IPv6 Linux loopback with native one/four threads and Bun: byte preservation, empty packets, exact/short capacity, invalid capacity, successive packets from distinct peers, invalid bind arguments, occupied ports and IPv6-only binding. Binary sends validate endpoint shape and every byte before sending, preserve empty packets, and leave the socket usable after rejection. IPv4 destination endpoints require unused address words and scope to be zero; destination ports must be 1 through 65,535. Payloads above 65,535 are rejected before transmission, and lower OS limits return the OS error. An invalid byte takes EINVAL precedence, including after an oversized prefix.

Remaining: scoped IPv6 interfaces, broader cancellation/resource stress and baseline performance comparisons. Do not adopt the candidate until the required checks are completed. Other OSes remain unvalidated.

## Cancellable reads

`UDPRead.new` takes ownership of a socket and returns an affine read operation plus a copyable cancellation handle. `UDPRead.wait` consumes the operation and returns the socket with `None` for cancellation or `Some` containing the normal packet/error result. `UDPRead.release` returns an unstarted operation's socket. Completion and release retire the cancellation capability; repeated and stale cancellation return false. A cancelled read never shuts down the socket or manufactures an empty packet.

Prepare `build/bend-udp-cancel-candidate` with the same preparation command and base, then run `python3 tests/udp_cancel_check.py`. The implementation removes only its own wait from the existing IO queue. Native slots use generation-checked capabilities and retire before reuse; JavaScript uses distinct operation objects. All operations run on the IO loop thread. Packet completion already committed by that loop wins over later cancellation.

Validated so far: pre-wait and parked cancellation, competing/repeated cancels, stale capabilities across slot reuse, unstarted release, successful packets, invalid receive limits and subsequent socket use. Native fixture audits check live operation rows, channels, queued waits and sockets. Sampled packet-arrival races and the Bend abort/deadline wrapper are also validated; see the parity records and `tests/udp_read_race_check.py`. Performance comparison and broader resource stress remain before adoption.

## Cancellable writes

`UDPWrite.new` takes ownership of the socket and validates/buffers one datagram without sending it. `UDPWrite.wait` consumes the operation and returns the socket with `None` for cancellation or `Some` containing the send result. `UDPWrite.release` discards an unstarted operation and returns its socket. Completion/release retire the cancellation handle; repeated or stale cancellation returns false. Cancellation cannot undo a completed send. The primitive neither duplicates nor shuts down the socket.

Prepare `build/bend-udp-write-candidate` using the command above and the same base. Run `python3 tests/udp_write_check.py`, then `python3 tests/udp_write_backpressure_check.py`, and `bun tests/udp_queued_cancel_check.js`. The first runner checks 72 owned-send scenarios on IPv4/IPv6 with native one/four threads and Bun, including empty/binary datagrams, rejection, pre-wait cancellation, release, stale handles and subsequent socket reuse. Native teardown audits cover live write rows, channels, parked waits and sockets in fd range 0–4095. The backpressure runner injects EAGAIN into generated test-only copies to exercise cancellation and resumption in 12 cases. It does not demonstrate real OS send-buffer saturation. The deterministic JS check covers parked and ready-but-not-yet-run cancellation for both operation types, with stubbed syscalls.

The JS IO loop removes ready waits before running their continuations. Cancellation of an operation in that intermediate state must be retained and observed by its queued wakeup; readiness alone is not completion. The candidate now handles that state for both reads and writes. No compiler scheduler change is required. The candidate remains uninstalled pending performance comparison and broader stress; non-Linux platforms remain unvalidated.

## Performance comparison

`python3 tests/udp_performance_check.py` builds the same loopback fixture with the current isolated candidate and a baseline containing the UDP send/receive effects from commit `8cc63fc` (before cancellation refactoring). It verifies that all other candidate files match. Every iteration sends one packet to the socket's own bound endpoint, then checks complete payload equality, the truncation flag and source port. The fixture covers IPv4/IPv6 and empty/256-byte datagrams on native one/four threads and Bun. Seven paired measured trials follow a warmup; version order alternates. Defaults are 30,000 exchanges per process. `--backend Bun --iterations 100000 --trials 9` runs the longer targeted comparison.

Results retain individual whole-process timings, CPU time, peak RSS, compiler/source hashes and guarded build measurements. Bootstrap intervals describe variation in the observed paired sample; they are not a proof of performance neutrality. Startup, payload construction and verification are included. The host is not CPU-isolated. This fixture does not measure cancellation overhead, concurrent operations, genuine OS backpressure, scoped IPv6 or non-Linux performance. No automatic installation follows from a result.

## Concurrent ownership stress

Run `python3 tests/udp_concurrent_check.py` after preparing `build/bend-udp-write-candidate`. It validates 24 scenarios with up to 128 simultaneously parked reads and 128 buffered unstarted writes, over up to 100 waves on IPv4/IPv6 and native one/four threads/Bun. Retained old handles are checked after the next wave allocates owners. Native audits require empty operation/resource state and slot tables bounded by concurrency width; generated test-only instrumentation verifies actual parked-read concurrency. Writes alternate cancellation and release. This does not exercise simultaneous parked writes or establish general leak freedom. Individual process time/RSS and exact audit results are retained in the parity record.
