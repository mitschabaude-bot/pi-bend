# Native hosts-file layer

`hosts-file` parses decoded hosts text into immutable address/name/alias entries. IPv4 requires four decimal octets; abbreviated, hexadecimal, octal and leading-zero forms are rejected. IPv6 uses the existing strict parser, including embedded IPv4. Brackets, ports and interface-zone suffixes are not address tokens. This uses the address grammar of `inet_pton`, as does the pinned [glibc hosts parser](https://raw.githubusercontent.com/bminor/glibc/glibc-2.39/nss/nss_files/files-hosts.c).

ASCII whitespace separates fields; `#` ends a line, including inline comments. Blank/comment lines contribute no entries. Each nonempty line requires an address and canonical name, followed by optional aliases. Names are retained as literal tokens, including spelling and aliases. ASCII letters compare without case sensitivity; other code points and trailing dots remain significant. This layer does not perform IDNA conversion or DNS hostname validation on name tokens. Non-whitespace C0 controls and DEL in parsed fields are rejected; ignored comment text is not interpreted.

Parsing returns either the complete ordered database or the first typed failure with a one-based natural-number line number. Malformed input never yields a partial success or gets silently skipped. This applies the user's approved strict malformed-input policy instead of the reference parser's skip-invalid-line behavior. The parser does not choose a fallback policy on file IO errors.

`hosts.Entry<Address>` and `hosts.lookup` are generic over address values. Lookup preserves each matching row, duplicate address occurrences, canonical spelling and aliases in file order. It supplies rows for higher-level address-family and canonical-name policy rather than implicitly mapping IPv6 addresses to IPv4 or selecting one family.

Generic laws cover concatenation of lookup results, empty lookup, canonical-name and alias matching, retention of matched entries, first-failure retention and rejection of partial databases. The concatenation proof is inductive over arbitrary entry lists. These laws do not prove the numeric address parser, all case-folding behavior, IO ownership or resource bounds. Executed tests use `inet_pton` for addresses and a separate test-only grammar/lookup oracle for the remaining behavior.

File loading, NSS/source ordering, address-family policy and dispatch into the native DNS resolver remain unimplemented for this layer. No production host-resolution path has been changed by adding this pure core.
