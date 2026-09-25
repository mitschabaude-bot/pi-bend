# Native response ownership

`http-response` adapts an affine event transport into a response metadata value and a body cursor. `startWith` reads through informational heads, returns at the first final head, and transfers the untouched successor transport state into the body. It neither waits for completion nor consumes the next body event. `nextWith` returns nonempty byte chunks and an affine successor; `closeWith` retires the owner early. Callers must consume or close it before disposing borrowed abort signals. Affine typing prevents duplicating the cursor, but dropping an affine value does not run cleanup automatically.

The adapter accepts explicit read/close functions over an arbitrary affine state type. Reads must return the successor on success, EOF and failure. Close consumes that state and must relinquish its resources even when reporting an error. `http-exchange-response` supplies these operations for the native socket exchange, preserving its upload task, buffered parser events and callback owner. The resolved HTTP startup report can transfer its successful exchange directly to this adapter; no second connection or request is created.

`Metadata.bodyPresent` controls public body exposure. HEAD and null-body responses still carry a transport owner that must be consumed or closed. In particular, a 205 response can have framed wire bytes to drain while exposing no body. This internal owner is not a claim that the eventual public Fetch response exposes a non-null body for those statuses. Hidden bytes are discarded, while transport failures remain observable through owner operations.

Body completion retains trailers and closes the transport owner before returning EOF. The parser may already have released its byte lease while events remain buffered; the close also retires the remaining exchange callbacks. Early close discards unread events. Read/protocol errors retain the original typed error; a simultaneous close failure is returned alongside it. Every terminal operation returns a closed successor, so further reads/closes perform no transport IO or repeat the error. Unexpected event ordering and EOF without a final head/completion reject explicitly.

The generic effect loops `seek` and `drive` have local `@unsafe` termination annotations: an external reader determines progress, and injected readers can emit arbitrarily many informational heads or empty chunks. The actual HTTP parser applies its existing informational limit. No arbitrary second limit is added to the public adapter. These annotations do not supply proof evidence. The pure progress module contains no unsafe definitions, and the law/proof root's existing unsafe audit is unchanged.

## Validation

Ten generic laws cover arbitrary head metadata, exposed byte preservation, empty/hidden chunks, completion trailers, hidden-body error preservation and separate/simultaneous cleanup errors. The proof gate checks 216 public laws and 57 supporting lemmas and rejects 132 typed mutations, including erased chunks/trailers and overwritten primary errors. These prove pure transition properties, not universal IO termination or resource safety.

The injected-source fixture checks 38 exact IO traces on each of native one/four threads and Bun. It checks the final-head handoff, chunk sequencing, hidden/empty body handling, completion, early close, pre/post-head errors, simultaneous cleanup failure and repeated operations on closed cursors. Deliberately unread trailing failures ensure that startup/early close/completion do not overread the source.

The native socket fixture adds 11 cases per backend against actual loopback HTTP peers: fixed/chunked/EOF bodies, informational heads, HEAD/204/205 behavior, early close, abort while waiting for body bytes, truncated bodies and malformed heads. Peers verify the request target/method and eventual client EOF. Abort preserves the supplied `stop` reason. This fixture does not inspect generated runtime allocation tables, so it establishes peer closure and observable ownership behavior rather than claiming a complete allocation audit.

Socket validation uses the clean `cd8da50` worktree plus the explicitly recorded new metadata/response/adapter files. Existing dependencies are checked against that commit; the earlier form-body drafts are excluded. The unchanged isolated compiler completes C emission in 51.94 seconds at 3,808,336 KiB peak sampled process-group RSS, producing 29,217,723 bytes of C. No compiler patch was added or installed.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 scripts/check-proofs.py
python3 tests/http_response_check.py
python3 tests/http_exchange_response_check.py --worktree "$PWD/build/http-resolved-clean"
```

## Acquired SSE byte source

`http-body-source` now consumes an affine body into a serialized owner and lends an `sse-reader.Source` containing read/close callbacks. Its error mapping is explicit and typed, so provider code can classify cancellation without matching strings. Bytes pass through unchanged; UTF-8/SSE decoding remains in the existing reader. Calls retain the serial resource token across the complete asynchronous operation. The owner stores its release operation, so disposal cannot accidentally select a different transport close function.

Retire all callback aliases and in-flight calls before disposal. The owner retires both callback factories, takes and retires the serial resource, then closes the remaining body. This last step is necessary for an unread body: closing a fresh SSE cursor intentionally does not call the source's close callback. Completion/error/early-close successors are already closed, so subsequent disposal causes no repeated transport close. A close error is returned once; disposal of that closed successor succeeds rather than repeating it. The source is one acquired reader; it does not implement body cloning or multiple independent reads.

Five generic laws preserve bytes, distinguish EOF from an empty chunk, apply the supplied read/close error mapping, and prove that releasing an already-closed body equals an immediate successful IO return for every transport close function. The proof root imports the existing response and SSE loops, raising its audited concrete annotation count from four to seven; the proofs neither invoke those loops nor claim their termination. No unsafe annotation is added by this adapter.

All 33 integration cases pass on native one/four threads and Bun, both unmodified and audited. They compose an injected asynchronous HTTP event source with the real serial/callback owner and SSE reader. Cases cover unread disposal, early return with buffered SSE events, normal completion, read/cleanup failures, unfinished events at EOF, and every split of a multibyte UTF-8 event. Two concurrent source reads yield distinct successive chunks across an explicit asynchronous suspension; their acquisition order is unspecified. Native audits return live channels and parked IO to zero; Bun audits additionally check its live/waiting IO counts. This is finite ownership/concurrency evidence, not a universal scheduling proof or a real socket/SSE integration test.

```sh
python3 tests/http_body_source_check.py
```

`http-exchange-response.source` supplies the concrete byte-source factory for a native socket body and a caller-provided typed error mapping. All 42 socket/SSE executions pass across native one/four threads and Bun, in production and audited builds. Real peers exercise fixed/chunked/EOF bodies, seven-byte socket reads, one-byte HTTP chunks splitting a multibyte SSE payload, early return, unread disposal, body truncation and unfinished SSE events. Peers observe client EOF. Native audits return live channels, parked IO and sockets in descriptors 0–4095 to zero; Bun audits return explicit channels and live/waiting IO to zero. This composition uses the same clean pinned worktree plus recorded new files, excluding form drafts.

```sh
python3 tests/http_exchange_sse_check.py --worktree "$PWD/build/http-resolved-clean"
```

[Native OpenAI Responses-reader composition](openai-responses.md) now consumes this source. The canonical assistant processor is also connected through this owner. [Bounded bytes/text/JSON body consumption](http-body-consumption.md) is also implemented. Provider policy, TLS, redirects, decompression, pooling and full native provider adoption remain pending. This is response ownership and acquired streaming atop the existing cleartext exchange, not completion of Fetch or the pi port.
