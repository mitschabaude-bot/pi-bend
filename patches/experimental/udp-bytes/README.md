# Binary datagram candidate

Additive `UDP.recv_bytes` prototype. Prepare with `python3 scripts/prepare-udp-candidate.py build/bend-udp-bytes-candidate --base build/bend-interface-index-candidate`, then run `python3 tests/udp_bytes_check.py`. It has not been installed.

The numeric endpoint layout matches `Socket.endpoint`: family, four address words, port and scope. A datagram is consumed atomically; the returned byte list is limited to `max`, and the flag indicates discarded excess bytes. Zero-length packets are successful values. The accepted capacity range is 0 through 65,535. Invalid capacity preserves the socket and consumes no packet.

Validated so far: IPv4 Linux native one/four threads and Bun, byte preservation, empty packets, exact/short capacity, invalid capacity, and successive packets from distinct peers. Remaining: IPv6 binding/validation, binary sends, cancellation races, resource-lifetime audits and baseline performance comparisons. Do not adopt the candidate until those checks are completed.
