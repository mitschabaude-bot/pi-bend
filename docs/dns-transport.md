# Resolver transport work

The reusable resolver implemented so far is explicitly TCP. The OS loader produces settings and diagnostics; it does not yet select UDP or provide complete system hostname resolution. Hosts files, address-family ordering, UDP exchanges, EDNS fallback and final configuration acceptance remain required work.

## Scheduling boundary

The pinned [glibc 2.39 transport implementation](https://raw.githubusercontent.com/bminor/glibc/glibc-2.39/resolv/res_send.c) distinguishes the transports. `__res_context_send` makes one server pass for TCP; the `attempts` count drives UDP rounds. TCP permits one reconnect for a reset during length-prefix reading. The parsed retransmission interval is used by the UDP path. Its timeout depends on server index and server count, with a minimum of one second. These details belong to the datagram scheduler, not a new outer retry loop around the TCP resolver.

Our explicit total deadline remains a caller limit spanning TCP candidates, aliases, server failover and the permitted reset recovery. Keeping that deadline also avoids inheriting the reference TCP path's blocking-wait behavior. Parsed timeout/attempt values remain in the retained configuration for the UDP implementation.

## Next implementation

The existing Bend UDP effects use string payloads and IPv4 socket addresses. Their receive path also omits a truncation indicator. DNS needs binary payloads, IPv4 and IPv6 endpoints, and explicit detection of truncated datagrams. Extend those low-level effects in an isolated candidate, then measure correctness and relevant performance before adoption. Keep DNS parsing, query matching, retry decisions, EDNS policy and search behavior in pure Bend.

The datagram API must preserve datagram boundaries and zero-length packets, distinguish an empty packet from EOF, expose the peer endpoint, reject invalid lengths/bytes, and close or cancel pending operations without leaked resources. Validate it against loopback sockets with binary/non-UTF-8 payloads, oversized packets, both address families and cancellation races. Integrate a pure scheduling state machine with generic laws before wiring the UDP driver into transport selection and TCP fallback.
