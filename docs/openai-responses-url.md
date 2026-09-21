# Strict Responses request URLs

`api/openai-responses-url.bend` prepares the fixed `/responses` resource URL used by pi's OpenAI Responses provider. It composes the existing native absolute URL parser and Unicode/IDNA tables with strict query decoding and RFC 3986 query-component encoding. It is a pure library component; the caller owns and supplies the immutable Unicode context. It does not access credentials, environment, sockets or clocks.

Joining follows SDK 6.40.0 `client.buildURL('/responses', undefined)`: one trailing base slash suppresses the resource path's leading slash. This is string concatenation before URL parsing, so a base containing a query or fragment follows that ordering as well. General relative-resource resolution and SDK default-query configuration are not exposed here because pi's Responses call does not supply them. Existing endpoint preparation remains responsible for HTTP scheme and credential validation.

Decoded query fields are collected into the native persistent record. Repeated names retain the last value and the first insertion position. Numeric-looking names keep ordinary insertion order; we do not recreate JavaScript integer-property enumeration. Query names and values use RFC 3986 encoding, including `%20` for spaces and `%2A` for `*`. Form body encoding remains a separate format. URLs without query entries retain their original query representation, including empty separator-only queries, matching the SDK's conditional normalization.

`runtime/src/url-form-strict.bend` rejects incomplete/nonhexadecimal percent escapes and malformed UTF-8. It preserves valid Unicode, a leading BOM, repeated names, empty names/values, and encoded delimiters. Only the first literal `=` splits a field. Plus signs decode as spaces. `parse` consumes a form body; `query` additionally strips one leading question mark. Errors distinguish the name from the value and retain the zero-based ampersand-separated field position, including skipped empty fields. Names are checked before values, and the first error is retained. Error values do not contain field contents.

This is the provider input boundary requested by Gregor. The older URLSearchParams-compatible parser remains explicitly permissive for callers that require that protocol API. The production Responses URL builder uses the strict module. The existing general URL parser still supplies its standard normalization behavior; these changes do not claim strict rejection of every noncanonical URL spelling.

## Correctness scope

Ten strict-parser laws cover decoded-value preservation, component/position error preservation, name-error precedence, immutable accumulation, empty-field behavior, first-error preservation and the leading query marker. Seven URL laws cover query-dictionary folding across arbitrary partitions, singleton field application, query replacement, typed URL/query failures and preservation of absent/empty queries. These are universally quantified equations and meaningful empty-input boundaries, not laws naming regression examples. Encoding round trips and end-to-end parser correctness are still supported by executed external comparisons rather than a full formal theorem.

`tests/openai_responses_url_check.py` checks the strict parser against an independent byte-oriented Python percent/UTF-8 decoder. It calls the actual installed OpenAI SDK's `buildURL` method without network access and compares resulting URLs. Approved strict-error and numeric-key-order differences are retained individually. RFC 3986 encoding is checked against Python's encoder, including ASCII characters, Unicode and a supplementary character crossing the SDK encoder's 1,024-unit chunk boundary. The fixture also covers repeated keys, BOMs, invalid escape bytes, first-error positions, Unicode hosts, ports and URL joining.

The component still needs joining to prepared payloads, native header construction, body serialization and transport/session dispatch. It is not a complete native OpenAI provider, and no upstream pi suite status is promoted.

## SDK encoder discrepancy

The installed SDK 6.40.0 query encoder splits a JavaScript string into 1,024-code-unit chunks before handling surrogate pairs. For `'x'.repeat(1023) + '🙂x'`, a pair is split across chunks: the SDK suffix becomes `%F0%9F%90%80%F2%A0%A1%B8` instead of `%F0%9F%99%82x`. Moving the same character one position left or right removes the corruption. The fixture calls the actual SDK encoder, records its output and verifies Bend against Python's UTF-8 RFC 3986 encoder. The retained difference is an external reference defect, not a reason to corrupt native scalar strings or introduce UTF-16 chunking. This follows the approved policy of preserving meaningful behavior without reproducing legacy runtime flaws.

## Validated milestone

The [proof record](proof-validation/2026-09-21-openai-responses-url.json) checks 356 public laws and 62 supporting lemmas, rejects 200 well-typed mutations, and checks open-obligation and missing-proof rejection. The existing unsafe audit is unchanged; these modules and their proofs add no unsafe declarations.

The [runtime record](runtime-validation/2026-09-21-openai-responses-url.json) contains 501 form-parser cases, 501 query-parser cases, seven encoder cases and 100 actual SDK URL comparisons on native one/four threads and Bun: 3,327 executed comparisons. It retains 43 deliberate strict-query rejections, one native numeric-name ordering difference, and the independent SDK encoder observations. Source, compiler, SDK and artifact fingerprints are recorded. No network access or real credentials are needed for these tests.

The installed compiler's C emission crossed a 12 GiB guard after 31.12 seconds and was stopped. Installed JS emission completed in 11.75 seconds at 5,793,608 KiB sampled group RSS. The unchanged isolated candidate completed native emission plus Clang compilation in 711.20 seconds at 10,730,688 KiB sampled group RSS. Its C output is 15,014,902 bytes. These are observational build costs, not a controlled speed comparison; the installed native build did not complete. The [compiler record](bend-issues/2026-09-21-openai-responses-url-compiler.json) retains both attempts, phase measurements and fingerprints. No compiler patch was changed or installed.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 scripts/check-proofs.py
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" python3 tests/openai_responses_url_check.py
```

The runner guards native rebuilds at 16 GiB and JS rebuilds at 10 GiB; it reports compiler failure rather than silently changing compilers. `--no-build` reuses already-built artifacts and is appropriate only when their sources have been verified unchanged.

## Empty-base oracle correction

Envelope integration revealed that the initial URL oracle parsed the raw joined address before calling the SDK. For an explicit empty base this reported a URL error without observing the SDK constructor's fallback to `https://api.openai.com/v1`. The corrected oracle now calls the actual SDK first and records that fallback separately. The native URL builder deliberately continues rejecting the empty value under the approved strict-configuration policy. The revised 1,109-case corpus passes on native one/four threads and Bun without a production URL-code change; [the correction record](runtime-validation/2026-09-21-openai-responses-url-oracle-correction.json) preserves the accurate SDK observation. The initial record is retained as historical evidence, not overwritten to hide the oracle error.
