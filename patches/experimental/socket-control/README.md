# Socket interruption — isolated implementation candidate

This bundle adds `Socket.duplicate` and `TCP.shutdown` to Base, with native and Bun syscall effects. `scripts/prepare-socket-candidate.py` combines them with the existing TCP byte effects in a fresh compiler copy. It changes no compiler or scheduler source and leaves the installed compiler untouched. Missing transport primitives are our implementation work.

```sh
python3 scripts/prepare-socket-candidate.py build/bend-socket-candidate-fresh
python3 tests/socket_interrupt_check.py build/bend-socket-candidate-fresh
```

`Socket.duplicate` retains the original affine socket and returns a typed result containing a second affine socket. The effect uses `fcntl(F_DUPFD_CLOEXEC)`, so the new descriptor is close-on-exec. Both owners refer to the same socket state and must be closed separately. Duplication failure returns the original owner unchanged. The platform constant for the Bun backend is 1030 on Linux and 67 on Darwin; Darwin remains untested. See the [Linux descriptor duplication contract](https://man7.org/linux/man-pages/man2/dup.2.html) and [Apple's fcntl definitions](https://github.com/apple/darwin-xnu/blob/main/bsd/sys/fcntl.h).

`TCP.shutdown` disables both directions through `shutdown(SHUT_RDWR)` and returns the same owner with a typed result. It does not close the descriptor. Pending socket IO can settle while its owner remains valid. Shutdown is destructive connection cancellation, not cancellation of one operation while preserving a reusable connection. Buffered received data can still be returned; the higher-level abort state must decide whether to expose it. A read settling with EOF after local shutdown must not by itself be interpreted as successful HTTP completion.

`packages/runtime/src/socket-interrupt.bend` manages the duplicate in a pure Bend serial resource. Its affine owner lends a duplicable handle; competing cancellation calls serialize on the interrupt descriptor independently of the original socket's IO. The first call shuts down and closes the duplicate, returning `Done(True)` or a typed error. Later calls return `Done(False)` without a syscall. Normal disposal closes the duplicate without shutdown, preserving the original connection. All handle users must be joined before disposal; handles are borrowed capabilities, not valid after owner retirement. The owner costs one additional descriptor and one channel until cancellation/disposal, with no permanent cancellation registry.

The test passes on native one/four threads and Bun under Bend 2.0.7/Bun 1.4.0 on Linux. Per backend it observes 12 reads parked in the scheduler and 12 writes parked after EAGAIN before cancellation, two competing cancellers with exactly one winner, repeated cancellation, and normal disposal followed by successful communication. A retained interrupt owner also survives closure of its original descriptor: another connection reuses that descriptor number, cancellation still targets the old connection, and the new connection communicates successfully. The compiler rejects copying the interrupt owner. Existing TCP byte contract tests also pass on native one/four threads and Bun, including invalid/empty sends, zero/partial reads, repeated EOF, reset reads and sends after reset.

Test-only instrumentation checks 26 successful duplicates with close-on-exec set, 25 shutdown calls and 53 close calls covering both descriptors for each duplicated connection plus the replacement connection. These are finite lifecycle observations, not a general leak/race proof. The test reduces socket buffers to ensure send backpressure and instruments only a disposable compiler copy. Its ordinary TCP fixture produces byte-identical C and JavaScript under the baseline and uninstrumented candidate. This establishes unchanged generated runtime code for that fixture, not general compiler performance neutrality. Before installation, broader compatibility and relevant performance comparisons remain required. Duplication failure under descriptor exhaustion, shutdown errors, connection establishment cancellation, TLS and provider integration remain implementation/validation work. Connection-level AbortSignal and dedicated HTTP source integration are described below.

## AbortSignal and HTTP integration

The candidate now also supports `runtime/src/abortable-socket.bend` and `runtime/src/http-socket-source.bend`. The first maintains one interrupt owner and one abort observation across the whole connected-socket lifetime. The second provides dedicated-connection callbacks to the HTTP response reader. Both implementations are pure Bend and add no primitive/compiler changes. Their checks run real loopback sockets on native one/four threads and Bun:

```sh
python3 tests/abortable_socket_check.py build/bend-socket-candidate-fresh
python3 tests/http_socket_source_check.py build/bend-socket-candidate-fresh
```

These checks cover retained abort reasons, observation/watch cleanup, normal EOF, HTTP body completion and truncation, early response closure and invalid read size. The concrete HTTP adapter closes its dedicated connection rather than returning it to a pool. Socket adoption begins after connection establishment; connect cancellation, DNS, TLS, request transmission and provider integration remain outstanding. These tests do not establish general race/leak freedom or compiler performance neutrality.

A complete buffered cleartext exchange can now be composed from the request-head encoder, UTF-8 encoder, abortable socket and response decoder. `python3 tests/http_request_exchange_check.py build/bend-socket-candidate-fresh` verifies 12 JSON POST exchanges on each native thread configuration and Bun against actual Node Fetch wire captures. This does not yet supply URL preparation, automatic request-body framing, streaming uploads or the provider wrapper.

The request exchange check now applies `http-buffered-body` and `http-buffered-framing` automatically, alternating ordinary fixed-length POSTs with chunked DELETEs selected by an explicit zero-length declaration. It preserves entity content separately from the encoded wire body. Complete captures still match actual Fetch on native one/four threads and Bun; general streaming uploads and the higher-level request/provider wrapper remain unfinished.

The composed exchange is now implemented by `http-buffered-request` and `http-socket-exchange`, including automatic callback/source retirement at EOF and error. Additional candidate checks are:

```sh
python3 tests/http_socket_exchange_check.py build/bend-socket-candidate-fresh
python3 tests/http_exchange_write_error_check.py build/bend-socket-candidate-fresh
```

The latter injects a body-send EPIPE into a disposable compiler copy and checks error retention and closure of all three descriptors. Production effects are unchanged. The driver now uploads concurrently with reads; upload failures arrive through response reads.

## Concurrent reads and writes

`runtime/src/socket-writer.bend` duplicates the connected socket for an independently owned upload while borrowing the original connection's AbortSignal scope. It adds no observation or primitive. Close and join writers before retiring the original connection; ordinary writer close preserves the shared connection. The independent descriptors allow response reads during backpressured upload writes.

```sh
python3 tests/socket_writer_check.py build/bend-socket-candidate-fresh
```

On native one/four threads and Bun, the test requires eight uploads to park before the peer sends early replies without draining upload data. The client reads each reply while its uploader remains unfinished, aborts, joins the writer and retires the connection. The peer verifies the exact partial upload prefix. Ordinary transmission, communication after writer close, pre-aborted creation, affine ownership and all 29 descriptor closes also pass. The HTTP exchange driver now uses this prerequisite for concurrent upload ownership and early-response settlement. Instrumentation changes only a disposable compiler copy, and the installed compiler remains unchanged.


`runtime/src/socket-upload.bend` owns the upload task and its settlement state. The HTTP source owns it alongside the read connection, stopping and joining it before connection disposal. Intentional interruption after response completion or early close does not abort the caller's signal or replace the response with a shutdown-induced write error. Genuine upload failure wakes the reader and remains a typed error. Run `python3 tests/http_early_response_check.py build/bend-socket-candidate-fresh` for 15 backpressured early-response lifecycles per backend, including complete and truncated bodies and early consumer close; each run checks all 45 descriptor closes. `python3 tests/http_early_response_oracle.py` checks corresponding public outcomes against actual Node Fetch. Neither check proves all race interleavings or performance neutrality.


## Reset classification and HTTP termination

The bundle also supplies `Socket.isConnectionReset(U32) -> IO(Bool)`. Its native effect compares against `ECONNRESET`; the Bun effect uses the platform errno (Linux 104, Darwin 54). This keeps OS error numbers out of pure Bend HTTP policy. It has no compiler or scheduler changes. Prepare a fresh candidate to include it; older candidate directories do not contain the new primitive.

```sh
python3 tests/socket_reset_classifier_check.py build/bend-socket-candidate-fresh build/bend-socket-candidate-baseline
python3 tests/http_reset_check.py build/bend-socket-candidate-fresh
```

The classifier checks 514 values on native one/four threads and Bun. The first check additionally requires byte-identical C/JavaScript for an unrelated TCP fixture against a pre-classifier candidate. Seven real-reset HTTP cases match actual Fetch, with the server waiting for client consumption of a response prefix before resetting. The pure HTTP reader decides whether reset can finish its current framing and exposes a distinct reset release reason. Aborts and other errors remain failures. The generic reader's 826 native lifecycle traces include reset and release-failure handling. These checks do not establish Darwin compatibility, all reset/upload race outcomes or broad performance neutrality; the candidate remains isolated.
