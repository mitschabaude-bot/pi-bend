The certificate benchmark measures fresh chain verification and its two certificate signatures against a test-only OpenSSL oracle. It does not contact a server, read credentials, or use the system trust store.

```sh
sh scripts/build-pure.sh tests/certificate-benchmark.bend build/certificate-benchmark
cc -O2 -Wall -Wextra tests/certificate-benchmark-openssl.c -lcrypto -o build/certificate-benchmark-openssl
python3 tests/certificate_benchmark.py tests/fixtures/tls/openai-public-chain.json --output build/certificate-times.json
```

The checked-in fixture contains only public certificates and a fixed validation time. The input JSON contains `argument`, the existing X509 runner's `limited:budget:epochHigh:epochLow:leafDER:peerDERs:anchorDERs` command, with decimal comma-separated bytes and `|` between certificates. This benchmark expects one anchor and an intermediate that signs the leaf and is signed by that anchor. It checks all verification results before reporting times.

Both implementations use the saved validation time, explicit anchor, SSL server purpose, and no hostname check. OpenSSL uses strict verification and partial-chain trust; its validation policy is not claimed to be identical on arbitrary malformed certificates. OpenSSL takes whole-second times, while Bend preserves milliseconds. The saved accepted chain must be away from a validity boundary for an equivalent comparison.

The reported body ratio is the performance criterion. The body timer excludes initial DER parsing and includes key and policy preparation, chain search, and signature verification. Bend includes writing one `ok` line to a pipe inside this interval. The separate process times also include startup and input parsing, so they are useful for end-to-end cost but cannot establish a cryptographic speed ratio. Each OpenSSL iteration reparses fresh certificate objects before starting its timer, preventing cached successful certificate signatures from producing an artificially fast result. Warm library state is allowed; cached verification results are not.

Keep sample arrays, binary hashes, and fixture hash with results. Compare matching single-thread native artifacts and avoid drawing conclusions from one sample or concurrent CPU-heavy builds. On Linux, `--cpu N` pins both implementations to one logical CPU; leave its sibling core free too. Oracle batches are interleaved with Bend samples. A successful TLS request alone does not satisfy the target of less than ten times OpenSSL's verification cost.

On 2026-09-22, commit `3b52eac` measured 7.790 ms for Bend and 0.806 ms for OpenSSL over 31 interleaved sample batches: a 9.67× ratio of medians, meeting the requested chain median target. The median paired ratio was 9.63×, with 28/31 pairs below 10× and a 90th percentile of 9.93×. Three outliers exceeded 10× on this shared host; this is not a worst-case guarantee. Individual leaf P-256 verification remained 32.61× OpenSSL, while intermediate P-384 verification was about 6.25×. [Raw samples, hashes and paired results](../docs/bend-issues/2026-09-22-certificate-verification.json) preserve the scope. The build uses the default `-O1`; no verification checks or benchmark work were removed.
