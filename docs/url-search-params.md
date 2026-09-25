# Immutable form/query tuples

`runtime/src/url-form.bend` and the url search params section of `url.bend` implement UTF-8 form encoding and persistent ordered name/value tuples. Repeated names are intentional protocol data, including repeated OAuth scopes; they are not object properties. Append, replacement and deletion return new values. Replacement retains the first matching position and removes later matches. Optional value-specific deletion removes only matching pairs. Lookups distinguish an absent name from a present empty value.

The optional sort operation follows the URLSearchParams API's stable UTF-16 name ordering; it does not sort requests implicitly. No JavaScript object reflection, prototype behavior, property enumeration or mutable iterator aliasing is involved. The encoder is directly useful for native form request bodies. The Responses URL component now uses strict parsing; body preparation and provider integration remain pending.

## Parsing boundary

The `parse` compatibility entry point implements the [URL Standard form parser](https://url.spec.whatwg.org/#concept-urlencoded-parser), including replacement-mode malformed UTF-8 and literal incomplete percent escapes. This is a compatibility parser, **not an approved strict provider-configuration boundary**. The project favors rejecting malformed configuration; the native provider path now uses the url form strict section of `url.bend`, which rejects malformed escapes/UTF-8 with typed component and field-position errors. Passing the compatibility corpus does not make its permissive parser the preferred configuration API. No meaningful upstream pi test is promoted by this work.

## Generic laws

Ten public laws establish ordered name/value projection over concatenation, scalar-normalization composition, preservation of head names and values, append-prefix preservation, deletion of matching heads, preservation of unrelated heads, deletion idempotence and empty lookup. One supporting induction lemma proves idempotence. These quantify over arbitrary entries, strings and optional deletion values. The conditional deletion laws quantify over evidence for matching/nonmatching entries, rather than selecting a few examples.

These laws do not yet prove the encode/parse round trip, set's first-position/uniqueness contract or sort correctness. Those remain proof work; the executed corpus covers their concrete behavior. The proof gate independently rejects type-correct mutations that drop projected names, drop projected values, discard an append prefix or retain entries that should be deleted.

## Differential evidence and reference-runtime defect

The query corpus has 1,141 cases, executed on native one/four threads and Bun (3,423 comparisons). Parsing expectations are independently checked using Python's byte-oriented percent decoder and UTF-8 replacement decoder. The Node oracle receives non-ASCII literal characters encoded as UTF-8 percent bytes; it retains every original ASCII delimiter and percent escape. Mutation operations, sorting and serialization still execute actual Node URLSearchParams.

The unmodified Node v24.18.0 parser disagrees with that byte-oriented oracle in 31 cases; the raw observations remain in the validation record. A reduced example is `x=%FFé🙂`: the standard yields a replacement character followed by `é🙂`, while raw Node yields two replacement characters followed by `=B`. `tests/url_search_params_node_reproducer.mjs` reproduces this without Bend or networking. Installed Node's `querystring` fallback writes UTF-16 code units into an eight-bit Buffer after `decodeURIComponent` throws; inspection of `internal/url` confirms its form parser calls that unescape function. This accounts for truncation of the literal non-ASCII input. We retain source hashes and do not copy this corruption into Bend.

The strict provider boundary rejects the malformed escape/encoding cases. Neither the oracle adjustment nor the compatibility parser changes that boundary. See [native Responses URLs](openai-responses.md).

## Validated milestone

The proof record checks 339 public laws and 62 supporting lemmas, rejects 193 well-typed mutations, and verifies rejection of open obligations and a missing proof. The existing 13-declaration unsafe source audit is unchanged; no new unsafe implementation or proof was added.

The runtime record retains the query comparisons and reference discrepancies, 1,110 buffered-body cases on each native thread configuration, and 24 complete JSON/form HTTP exchanges on each of native one/four threads and Bun. The exchange oracle performs another 24 Node Fetch requests. Peers verify framing, encoded bytes and client closure. Buffered-body checks cover default/preserved content type, empty forms, method rejection and invalid byte inputs. The socket fixture exercises both fixed-length and chunked form uploads; it does not claim TLS or complete provider assembly.

The compiler record records unchanged candidate fingerprints and guarded build measurements. Query C/JS emission took approximately 6.90/3.17 seconds with sampled peak group RSS of 1,582,868/1,172,824 KiB. Native exchange emission plus compilation took 69.68 seconds and 3,511,496 KiB. These are workload observations, not controlled before/after performance claims. No compiler patch was changed or installed.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 scripts/check-proofs.py
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 tests/url_search_params_check.py
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 tests/http_buffered_body_check.py
python3 tests/http_request_exchange_check.py build/bend-profiles/dns-transport-teles/bend2
```
