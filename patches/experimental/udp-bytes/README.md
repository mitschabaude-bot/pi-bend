# Binary datagram candidate

Additive `UDP.bind_family`, `UDP.recv_bytes` and `UDP.send_bytes` prototypes. Prepare with `python3 scripts/prepare-udp-candidate.py build/bend-udp-send-candidate --base build/bend-interface-index-candidate`, then run `python3 tests/udp_bytes_check.py build/bend-udp-send-candidate`, `python3 tests/udp_bind_check.py build/bend-udp-send-candidate` and `python3 tests/udp_send_check.py`. They have not been installed.

Binding accepts family 4 or 6 and port 0 through 65,535; zero requests an ephemeral port. IPv6 sockets are IPv6-only, and both families bind wildcard addresses. Sockets are nonblocking and marked close-on-exec. Every setup failure closes the newly allocated descriptor.

The receive endpoint layout matches `Socket.endpoint`: family, four address words, port and scope. A datagram is consumed atomically; the returned byte list is limited to `max`, and the flag indicates discarded excess bytes. Zero-length packets are successful values. The accepted capacity range is 0 through 65,535. Invalid capacity preserves the socket and consumes no packet.

Validated on IPv4 and IPv6 Linux loopback with native one/four threads and Bun: byte preservation, empty packets, exact/short capacity, invalid capacity, successive packets from distinct peers, invalid bind arguments, occupied ports and IPv6-only binding. Binary sends validate endpoint shape and every byte before sending, preserve empty packets, and leave the socket usable after rejection. IPv4 destination endpoints require unused address words and scope to be zero; destination ports must be 1 through 65,535. Payloads above 65,535 are rejected before transmission, and lower OS limits return the OS error. An invalid byte takes EINVAL precedence, including after an oversized prefix.

Remaining: scoped IPv6 interfaces, cancellation races, resource-lifetime audits and baseline performance comparisons. Do not adopt the candidate until the required checks are completed. Other OSes remain unvalidated.

## Cancellable reads

`UDPRead.new` takes ownership of a socket and returns an affine read operation plus a copyable cancellation handle. `UDPRead.wait` consumes the operation and returns the socket with `None` for cancellation or `Some` containing the normal packet/error result. `UDPRead.release` returns an unstarted operation's socket. Completion and release retire the cancellation capability; repeated and stale cancellation return false. A cancelled read never shuts down the socket or manufactures an empty packet.

Prepare `build/bend-udp-cancel-candidate` with the same preparation command and base, then run `python3 tests/udp_cancel_check.py`. The implementation removes only its own wait from the existing IO queue. Native slots use generation-checked capabilities and retire before reuse; JavaScript uses distinct operation objects. All operations run on the IO loop thread. Packet completion already committed by that loop wins over later cancellation.

Validated so far: pre-wait and parked cancellation, competing/repeated cancels, stale capabilities across slot reuse, unstarted release, successful packets, invalid receive limits and subsequent socket use. Native fixture audits check live operation rows, channels, queued waits and sockets. Sampled packet-arrival races and the Bend abort/deadline wrapper are also validated; see the parity records and `tests/udp_read_race_check.py`. Send cancellation, performance comparison and broader resource stress remain before adoption.
