# Native hosts-file layer

`hosts-file` parses decoded hosts text into immutable address/name/alias entries. IPv4 requires four decimal octets; abbreviated, hexadecimal, octal and leading-zero forms are rejected. IPv6 uses the existing strict parser, including embedded IPv4. Brackets, ports and interface-zone suffixes are not address tokens. This uses the address grammar of `inet_pton`, as does the pinned [glibc hosts parser](https://raw.githubusercontent.com/bminor/glibc/glibc-2.39/nss/nss_files/files-hosts.c).

ASCII whitespace separates fields; `#` ends a line, including inline comments. Blank/comment lines contribute no entries. Each nonempty line requires an address and canonical name, followed by optional aliases. Names are retained as literal tokens, including spelling and aliases. ASCII letters compare without case sensitivity; other code points and trailing dots remain significant. This layer does not perform IDNA conversion or DNS hostname validation on name tokens. Non-whitespace C0 controls and DEL in parsed fields are rejected; ignored comment text is not interpreted.

Parsing returns either the complete ordered database or the first typed failure with a one-based natural-number line number. Malformed input never yields a partial success or gets silently skipped. This applies the user's approved strict malformed-input policy instead of the reference parser's skip-invalid-line behavior. The parser does not choose a fallback policy on file IO errors.

`hosts.Entry<Address>` and `hosts.lookup` are generic over address values. Lookup preserves each matching row, duplicate address occurrences, canonical spelling and aliases in file order. It supplies rows for higher-level address-family and canonical-name policy rather than implicitly mapping IPv6 addresses to IPv4 or selecting one family.

Generic laws cover concatenation of lookup results, empty lookup, canonical-name and alias matching, retention of matched entries, first-failure retention and rejection of partial databases. The concatenation proof is inductive over arbitrary entry lists. These laws do not prove the numeric address parser, all case-folding behavior, IO ownership or resource bounds. Executed tests use `inet_pton` for addresses and a separate test-only grammar/lookup oracle for the remaining behavior.

Bounded file loading is implemented below. NSS/source ordering, address-family policy and dispatch into the native DNS resolver remain unimplemented for this layer. No production host-resolution path has been changed by adding this pure core.

## Bounded file loading

`hosts-load.readWith` reads a caller-selected path under an explicit source-byte limit and returns typed loading, decoding or syntax failures. This injectable entry point requires a decoder; there is no implicit replacement-decoding default. The standard `hosts-load.read` entry point uses strict UTF-8 as described below. A missing file is a loading error, not an empty database or permission to query DNS. The caller will choose that source/fallback policy when hostname resolution is integrated.

`bounded-file.readWith` is shared with resolver-file loading. Its pure `bounded-bytes` core retains at most the budget, tracks overflow across chunks and rejects the first excess byte. The IO adapter uses the existing file-fold owner to close before decoding. Exact-budget files succeed after EOF; oversized inputs stop without waiting for EOF. Read chunk size remains separately caller-controlled, so the byte-retention limit is not a bound on the size of an individual OS read or total process memory.

Four generic laws cover chunk composition, sticky overflow, exclusion of excess bytes and single-byte budget consumption for arbitrary values and retained prefixes. Live file and pipe tests check error precedence and closure. The resolver's existing `readWith`/`loadWith` entry points and error constructors remain unchanged; their internal budget state moved into the reusable core. OS source ordering and hosts-to-DNS dispatch remain pending.

## Strict UTF-8 default

`hosts-load.read` uses `utf8-strict.decode`, rejecting malformed encoding before hosts syntax parsing. It strips one leading UTF-8 BOM; later U+FEFF scalars remain text. `readWith` still supports an explicitly chosen alternate decoder. Malformed UTF-8 in comments is rejected too, since the entire bounded file is decoded before parsing. Source-size and IO failures still precede decoding.

`utf8-strict` reuses the existing decoder's continuation ranges, scalar assembly and BOM/output handling. Its initial state chooses `Preserve` or `StripLeading`, `feed` accepts chunks, and `finish` returns complete text or a typed error. Invalid byte values above 255 and irreparably malformed sequences retain the zero-based offset and offending value. Incomplete input reports the EOF offset. Offsets are natural numbers; errors remain sticky across later chunks. The failed result carries no accumulator or partial text. The existing replacement-mode decoder is unchanged.

The differential oracle uses Python's strict codec on each prefix. Its ordinary incremental decoder can defer rejection of a surrogate prefix such as `ED A0` until a subsequent byte; finalizing prefixes distinguishes already-malformed data from an incomplete prefix that can still become valid. This checks the strict decoder's earliest-offending-byte contract without implementing UTF-8 a second time in the oracle. Generic chunk/failure laws supplement, rather than replace, executed numeric boundary and malformed-input checks.
