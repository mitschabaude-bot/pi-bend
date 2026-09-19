# Numeric socket endpoints

This additive, uninstalled primitive exposes `getsockname` and `getpeername`. It returns the same affine socket on success and failure. It does not duplicate or close descriptors, resolve names, or change socket state. The pure Bend adapter in `packages/runtime/src/socket-endpoint.bend` supplies `Local`/`Peer` selectors, typed IPv4/IPv6 endpoints and typed errors. IPv6 scope is retained separately from its four address words.

Prepare a candidate with `python3 scripts/prepare-endpoint-candidate.py DEST [--base EXISTING_CANDIDATE]`. The preparer verifies that existing compiler and effect files remain byte-identical and Base receives only the declaration append. The installation is unchanged. For the live TCP fixture, the base candidate must also contain the owned connection and byte socket primitives used by that fixture.

Validation commands:

```sh
python3 tests/socket_endpoint_check.py build/bend-endpoint-candidate
python3 tests/socket_endpoint_layout_check.py build/bend-endpoint-candidate
python3 scripts/prepare-endpoint-candidate.py build/bend-endpoint-only-candidate
python3 scripts/benchmark-tcp-bytes.py build/bend-endpoint-only-candidate build/socket-endpoint-performance.json socket_endpoint.c socket_endpoint.js
```

The live Linux fixture compares local and peer metadata with independent Python socket observations for IPv4, IPv6 and IPv4-mapped TCP. Each connection repeats inspection and invalid-selector rejection 16 times, exchanging bytes afterwards to verify continued usability, then closes with peer-observed EOF. An unconnected UDP socket retains its local endpoint after peer inspection fails. All cases pass on native one/four threads and Bun: 144 TCP exchanges and three UDP cases.

Disposable syscall-boundary tests cover every address word, maximal port and scope values, zero fields, invalid selectors, syscall errors, unsupported families and short sockaddr lengths. All 96 cases pass. Native tests use the Linux ABI; the JS tests additionally simulate Darwin layouts. This does not establish actual Darwin FFI correctness. The test modifies generated disposable programs, not production effects.

The primitive has no resource table or scheduler integration. The JS FFI binding is cached lazily when the new effect first runs. Existing compiler controls measure unused-effect compilation only; they do not establish runtime throughput or cross-platform performance. Measurements and source hashes are retained under `docs/runtime-validation/2026-09-20-socket-endpoint*.json`. DNS response matching still needs to compose these observations with its transaction metadata.
