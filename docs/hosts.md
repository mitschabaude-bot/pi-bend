# Native hosts-file layer

`hosts-file` parses decoded hosts text into immutable address/name/alias entries. IPv4 requires four decimal octets; abbreviated, hexadecimal, octal and leading-zero forms are rejected. IPv6 uses the existing strict parser, including embedded IPv4. Brackets, ports and interface-zone suffixes are not address tokens. This uses the address grammar of `inet_pton`, as does the pinned [glibc hosts parser](https://raw.githubusercontent.com/bminor/glibc/glibc-2.39/nss/nss_files/files-hosts.c).

ASCII whitespace separates fields; `#` ends a line, including inline comments. Blank/comment lines contribute no entries. Each nonempty line requires an address and canonical name, followed by optional aliases. Names are retained as literal tokens, including spelling and aliases. ASCII letters compare without case sensitivity; other code points and trailing dots remain significant. This layer does not perform IDNA conversion or DNS hostname validation on name tokens. Non-whitespace C0 controls and DEL in parsed fields are rejected; ignored comment text is not interpreted.

Parsing returns either the complete ordered database or the first typed failure with a one-based natural-number line number. Malformed input never yields a partial success or gets silently skipped. This applies the user's approved strict malformed-input policy instead of the reference parser's skip-invalid-line behavior. The parser does not choose a fallback policy on file IO errors.

`hosts.Entry<Address>` and `hosts.lookup` are generic over address values. Lookup preserves each matching row, duplicate address occurrences, canonical spelling and aliases in file order. It supplies rows for higher-level address-family and canonical-name policy rather than implicitly mapping IPv6 addresses to IPv4 or selecting one family.

Generic laws cover concatenation of lookup results, empty lookup, canonical-name and alias matching, retention of matched entries, first-failure retention and rejection of partial databases. The concatenation proof is inductive over arbitrary entry lists. These laws do not prove the numeric address parser, all case-folding behavior, IO ownership or resource bounds. Executed tests use `inet_pton` for addresses and a separate test-only grammar/lookup oracle for the remaining behavior.

Bounded file loading is implemented below. The explicit files-first dispatch policy and family filtering are described below; system NSS configuration and the concrete native DNS adapter remain pending. No production host-resolution path has been changed by adding this pure core.

## Bounded file loading

`hosts-load.readWith` reads a caller-selected path under an explicit source-byte limit and returns typed loading, decoding or syntax failures. This injectable entry point requires a decoder; there is no implicit replacement-decoding default. The standard `hosts-load.read` entry point uses strict UTF-8 as described below. A missing file is a loading error, not an empty database or permission to query DNS. The files-first policy below retains that error as terminal.

`bounded-file.readWith` is shared with resolver-file loading. Its pure `bounded-bytes` core retains at most the budget, tracks overflow across chunks and rejects the first excess byte. The IO adapter uses the existing file-fold owner to close before decoding. Exact-budget files succeed after EOF; oversized inputs stop without waiting for EOF. Read chunk size remains separately caller-controlled, so the byte-retention limit is not a bound on the size of an individual OS read or total process memory.

Four generic laws cover chunk composition, sticky overflow, exclusion of excess bytes and single-byte budget consumption for arbitrary values and retained prefixes. Live file and pipe tests check error precedence and closure. The resolver's existing `readWith`/`loadWith` entry points and error constructors remain unchanged; their internal budget state moved into the reusable core. System source configuration and the concrete native DNS adapter remain pending.

## Strict UTF-8 default

`hosts-load.read` uses `utf8-strict.decode`, rejecting malformed encoding before hosts syntax parsing. It strips one leading UTF-8 BOM; later U+FEFF scalars remain text. `readWith` still supports an explicitly chosen alternate decoder. Malformed UTF-8 in comments is rejected too, since the entire bounded file is decoded before parsing. Source-size and IO failures still precede decoding.

`utf8-strict` reuses the existing decoder's continuation ranges, scalar assembly and BOM/output handling. Its initial state chooses `Preserve` or `StripLeading`, `feed` accepts chunks, and `finish` returns complete text or a typed error. Invalid byte values above 255 and irreparably malformed sequences retain the zero-based offset and offending value. Incomplete input reports the EOF offset. Offsets are natural numbers; errors remain sticky across later chunks. The failed result carries no accumulator or partial text. The existing replacement-mode decoder is unchanged.

The differential oracle uses Python's strict codec on each prefix. Its ordinary incremental decoder can defer rejection of a surrogate prefix such as `ED A0` until a subsequent byte; finalizing prefixes distinguishes already-malformed data from an incomplete prefix that can still become valid. This checks the strict decoder's earliest-offending-byte contract without implementing UTF-8 a second time in the oracle. Generic chunk/failure laws supplement, rather than replace, executed numeric boundary and malformed-input checks.

## Family selection and files-first dispatch

`hosts-family.lookup` applies name lookup and an explicit `Any`, `IPv4Only` or `IPv6Only` filter. It retains complete matching rows, canonical spellings, aliases, duplicate occurrences and file order. It does not map IPv4 into IPv6, sort addresses or select an implicit preferred family.

`hosts-resolve.plan` accepts a typed result containing an already-loaded immutable database. A source failure is terminal. A nonempty eligible result becomes `Local{first, rest}`; only an empty eligible result becomes `Query{family, name}`. A match exclusively in the wrong family therefore permits a network query. A local name is not parsed as DNS syntax, and no search suffix is applied to it. The miss preserves the original spelling for the network layer.

`resolveWith` executes that plan through an injected effectful lookup. Local results and source errors never call it; misses call it once. `Report` retains hosts rows or the complete generic network result as distinct variants, including any network error, metadata or canonical wire name. It does not invent TTLs for hosts entries or convert arbitrary local tokens into DNS names. This is an explicit files-then-network policy, not an implementation of system `nsswitch.conf`. Callers own snapshot loading/reloading and the network environment. A concrete adapter to the persistent native resolver, dual-family network orchestration and runtime adoption remain pending.

Seven generic laws establish arbitrary-database preservation for `Any`, filtering over concatenation, wrong-family exclusion, terminal source failure, empty-source query retention and local selection for nonempty eligible rows. The inductive concatenation law preserves order and duplicates. Executed callback traces check that local hits and malformed databases never query the network, and that misses call once with the original family/name and retain both successful and failed network reports. These are dispatch integration tests with an injected callback, not live DNS exchanges.
