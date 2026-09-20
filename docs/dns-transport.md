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

## Implemented retry sequence core

`dns-udp-schedule` now supplies a generic immutable cursor over repeated passes through one selected server order. It retains the order across rounds, preserves duplicate entries, emits one entry per step and exhausts without an attempt when the count or server list is empty. Its generic laws specify the entire remaining sequence. The driver must supply entries carrying original configuration indices before rotation: the pinned reference computes each server's timeout from that original index, not its position in the rotated visit order. Timeout construction, policy validation, transport transitions and actual UDP exchanges remain to be wired to this cursor. The pure scheduling work can proceed against the isolated runtime candidate without adopting its effects into the installed compiler.

## Implemented timeout calculation

`dns-udp-timeout` represents original positions as `First`, `SecondOfTwo`, `SecondOfThree` and `ThirdOfThree`. The supported domain comes from [glibc 2.39's three-server limit](https://raw.githubusercontent.com/bminor/glibc/glibc-2.39/resolv/bits/types/res_state.h). Within the [parsed timeout range 0–30](https://raw.githubusercontent.com/bminor/glibc/glibc-2.39/resolv/resolv.h), it implements the [datagram budget formula](https://raw.githubusercontent.com/bminor/glibc/glibc-2.39/resolv/res_send.c): the first server uses the base seconds, later original indices scale by their power of two and divide by server count, and every result has a one-second minimum. The largest supported result is 40 seconds. Direct inputs above 30 return a typed error; the existing option parser retains its documented cap.

The duration type represents strictly positive whole seconds. Generic laws cover positivity, preservation/flooring and equal budgets for both positions in a two-server setup. Compiled reference-formula checks cover every parsed base timeout and valid original position. Position assignment to configured entries, configuration acceptance for excess server entries, conversion into attempt deadline scopes and actual exchanges remain integration work. The timeout module does not decide those policies implicitly.

## Prepared server entries

`dns-udp-plan.prepare` now attaches position metadata before rotation and calculates each entry's duration. Its successful result is a complete list of `Attempt{server, position, duration}` values suitable for `dns-server-source`/`dns-server-rotation` and `dns-udp-schedule`; duplicate server payloads remain separate positioned entries. The UDP preparation boundary returns typed errors for zero or more than three entries, preserving strict rejection instead of silent truncation. This boundary is not yet used by the system loader or live resolver, so existing configuration acceptance remains unchanged. The loader still retains all source settings/diagnostics for final policy integration. Invalid layout errors precede timeout validation; no partial plan is exposed.

The remaining driver work must consume these prepared entries, create nested attempt deadlines under the caller's total deadline, encode/send queries, validate incoming peers and replies, choose retry/stop/TCP fallback, and retire each attempt before continuing. The composition fixture checks ordering and budgets without performing network exchanges.

## Attempt deadline scopes

`dns-udp-attempt-scope.create` now borrows the existing total-deadline signal and creates a child scope from a prepared duration. The checked conversion accepts the supported 1–40 seconds and rejects manually constructed larger durations before creating a timer. A generic law establishes rejection for any excess natural value. The child scope preserves its parent's reason: the adapter distinguishes local attempt expiry from parent abort, including the total deadline expiring and supplied/default caller aborts.

`close` must run after all operations borrowing the child signal settle. It delegates cancellation and joins to the existing deadline owner and returns the classified settled reason. Repeated attempts reuse the same total-deadline signal; they do not reset the caller's clock. Loopback exchange code must still own its socket, send and receive under this child signal, and finish cleanup before creating the next attempt. This adapter is validated against the isolated timer candidate and is not yet a complete UDP driver.
