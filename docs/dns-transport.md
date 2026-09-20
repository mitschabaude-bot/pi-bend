# Resolver transport work

The reusable resolver implemented so far is explicitly TCP. The OS loader produces settings and diagnostics; it does not yet select UDP or provide complete system hostname resolution. Hosts files, address-family ordering, UDP exchanges, EDNS fallback and final configuration acceptance remain required work.

## Scheduling boundary

The pinned [glibc 2.39 transport implementation](https://raw.githubusercontent.com/bminor/glibc/glibc-2.39/resolv/res_send.c) distinguishes the transports. `__res_context_send` makes one server pass for TCP; the `attempts` count drives UDP rounds. TCP permits one reconnect for a reset during length-prefix reading. The parsed retransmission interval is used by the UDP path. Its timeout depends on server index and server count, with a minimum of one second. These details belong to the datagram scheduler, not a new outer retry loop around the TCP resolver.

Our explicit total deadline remains a caller limit spanning TCP candidates, aliases, server failover and the permitted reset recovery. Keeping that deadline also avoids inheriting the reference TCP path's blocking-wait behavior. Parsed timeout/attempt values remain in the retained configuration for the UDP implementation.

## Next implementation

The original Bend UDP effects use string payloads and IPv4 socket addresses, without a receive truncation indicator. The isolated UDP candidate now supplies binary payloads, IPv4 and IPv6 endpoints, and explicit detection of truncated datagrams. Complete correctness, resource and relevant performance checks before adoption. Keep DNS parsing, query matching, retry decisions, EDNS policy and search behavior in pure Bend.

The datagram API must preserve datagram boundaries and zero-length packets, distinguish an empty packet from EOF, expose the peer endpoint, reject invalid lengths/bytes, and close or cancel pending operations without leaked resources. Validate it against loopback sockets with binary/non-UTF-8 payloads, oversized packets, both address families and cancellation races. Integrate a pure scheduling state machine with generic laws before wiring the UDP driver into transport selection and TCP fallback.

## UDP cancellation finding and implementation

The existing TCP socket-interrupt owner must not wrap pending UDP receives. A reduced Linux probe shows that shutdown on an unconnected UDP socket returns ENOTCONN; a connected socket accepts shutdown, but both then report readiness while nonblocking receive returns EAGAIN. The resulting receive callback parks again. All six Bend probes (IPv4/IPv6 on native one/four threads and Bun) remained pending for the bounded observation interval. [Evidence](runtime-validation/2026-09-20-udp-interrupt-investigation.json) records the OS and Bend observations. This is an unsupported composition, not evidence that the TCP interrupt contract is broken.

Implement operation-level cancellation in the isolated UDP candidate. Use the existing cancellable timer model: an affine operation owner, independently copyable cancellation capability, explicit completion/cancelled states, and queue removal on cancellation. A pending read must return socket ownership and a distinct cancellation outcome without manufacturing an empty datagram or shutting down the socket. Join the operation before retiring its owner. Stale cancellation capabilities must not affect a reused operation slot. Completion already committed by the IO loop must beat later cancellation. Keep all new state and cancellation work in the new effects so existing IO paths remain unchanged.

Validate cancellation before wait, while parked, after completion, repeated/competing cancellation, owner reuse, packet arrival races, and descriptor/activation cleanup. Only then wire abort/deadline scopes to the datagram driver. This is implementation work in this project; it is not a request for an external primitive to be supplied.

Both operation primitives are implemented in the isolated candidate as `UDPRead.new/wait/cancel/release` and `UDPWrite.new/wait/cancel/release`. Read packet-arrival races, cancellation/completion, stale capabilities and socket reuse are validated. Send parking, retry and cancellation use explicit test-only EAGAIN injection; real OS send-buffer saturation is not claimed. Native teardown audits check operation rows, timers, channels, parked waits and sockets in fd range 0–4095. Pure Bend `abortable-datagram.recv/send` wrappers register removable abort observations and join their watchers before returning. Existing generic abort-outcome laws cover final precedence for both result types. These milestones are detailed in the parity records. Broader concurrent resource stress and performance evaluation still precede adoption; the UDP driver and scheduling state machine remain to be implemented.
