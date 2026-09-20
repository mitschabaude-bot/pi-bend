# Binary datagram candidate

Additive `UDP.bind_family` and `UDP.recv_bytes` prototypes. Prepare with `python3 scripts/prepare-udp-candidate.py build/bend-udp-family-candidate --base build/bend-interface-index-candidate`, then run `python3 tests/udp_bytes_check.py` and `python3 tests/udp_bind_check.py`. They have not been installed.

Binding accepts family 4 or 6 and port 0 through 65,535; zero requests an ephemeral port. IPv6 sockets are IPv6-only, and both families bind wildcard addresses. Sockets are nonblocking and marked close-on-exec. Every setup failure closes the newly allocated descriptor.

The receive endpoint layout matches `Socket.endpoint`: family, four address words, port and scope. A datagram is consumed atomically; the returned byte list is limited to `max`, and the flag indicates discarded excess bytes. Zero-length packets are successful values. The accepted capacity range is 0 through 65,535. Invalid capacity preserves the socket and consumes no packet.

Validated on IPv4 and IPv6 Linux loopback with native one/four threads and Bun: byte preservation, empty packets, exact/short capacity, invalid capacity, successive packets from distinct peers, invalid bind arguments, occupied ports and IPv6-only binding. Remaining: binary sends, scoped IPv6 interfaces, cancellation races, resource-lifetime audits and baseline performance comparisons. Do not adopt the candidate until the required checks are completed. Other OSes remain unvalidated.
