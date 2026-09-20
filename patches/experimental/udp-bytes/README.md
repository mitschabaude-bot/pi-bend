# Binary datagram candidate

Additive `UDP.bind_family`, `UDP.recv_bytes` and `UDP.send_bytes` prototypes. Prepare with `python3 scripts/prepare-udp-candidate.py build/bend-udp-send-candidate --base build/bend-interface-index-candidate`, then run `python3 tests/udp_bytes_check.py build/bend-udp-send-candidate`, `python3 tests/udp_bind_check.py build/bend-udp-send-candidate` and `python3 tests/udp_send_check.py`. They have not been installed.

Binding accepts family 4 or 6 and port 0 through 65,535; zero requests an ephemeral port. IPv6 sockets are IPv6-only, and both families bind wildcard addresses. Sockets are nonblocking and marked close-on-exec. Every setup failure closes the newly allocated descriptor.

The receive endpoint layout matches `Socket.endpoint`: family, four address words, port and scope. A datagram is consumed atomically; the returned byte list is limited to `max`, and the flag indicates discarded excess bytes. Zero-length packets are successful values. The accepted capacity range is 0 through 65,535. Invalid capacity preserves the socket and consumes no packet.

Validated on IPv4 and IPv6 Linux loopback with native one/four threads and Bun: byte preservation, empty packets, exact/short capacity, invalid capacity, successive packets from distinct peers, invalid bind arguments, occupied ports and IPv6-only binding. Binary sends validate endpoint shape and every byte before sending, preserve empty packets, and leave the socket usable after rejection. IPv4 destination endpoints require unused address words and scope to be zero; destination ports must be 1 through 65,535. Payloads above 65,535 are rejected before transmission, and lower OS limits return the OS error. An invalid byte takes EINVAL precedence, including after an oversized prefix.

Remaining: scoped IPv6 interfaces, cancellation races, resource-lifetime audits and baseline performance comparisons. Do not adopt the candidate until the required checks are completed. Other OSes remain unvalidated.
