# Coding-agent messages

`core/messages.bend` ports pi-mono `46c9de402`, `core/messages.ts`. Named Bash/custom/branch/compaction records form the `CodingMessage<Details>` union stored in `Agent.AgentMessage.CustomMessage`. Custom details retain their caller-supplied type, content reuses text/image blocks, and ordinary LLM messages pass through unchanged. Conversion preserves input order, filters only excluded Bash messages, includes custom messages regardless of their display flag, and preserves timestamps. Bash command/output text and summary delimiters match the pinned formatting, including cancellation precedence, empty output, empty paths and the different branch/compaction suffix newlines.

`createBranchSummaryMessage`, `createCompactionSummaryMessage` and `createCustomMessage` preserve the source constructors but return `Result<Date.ParseError,...>` instead of introducing NaN timestamps. Nullable branch IDs and optional values use `Maybe`; token counts use `Nat`, and shell exit codes use `U32`, consistent with native execution. Neither fractional/negative token counts nor malformed JavaScript objects are represented.

Reusable `Date.parseIso` accepts `YYYY-MM-DDTHH:mm:ss[.fraction](Z|±HH:MM)` with uppercase T/Z and explicit offsets. It validates every digit, Gregorian leap days and clock/offset fields; seconds are 0–59, hours 0–23 and offset hours 0–23. Fractions require at least one digit and truncate to three millisecond digits without rounding or overflow. Calendar word arithmetic preserves pre-1970 milliseconds exactly before conversion to the existing F64 message timestamp. Locale-dependent forms, unzoned/date-only strings, invalid dates normalized by JS Date and leap seconds reject. Four-digit civil years 0000–9999 are an existing Calendar range limitation, not a claim that expanded ISO years are malformed or that all Date parsing is ported.

Valid long fractional precision intentionally follows exact decimal truncation rather than JS parser quirks. For example, Node and Bun parse `.0597925507326` in `0929-05-05T10:14:32.0597925507326-03:30` as 597ms; Bend retains 59ms. The oracle directly checks canonical timestamp inputs, while long-fraction checks independently assert the first three digits, including all-zero prefixes and a 1,003-digit fraction.

Bun and optimized native explicit one/four workers pass 378 pinned-source comparisons (186 dates and 192 Bash formatting combinations), 17 malformed/range cases, six long-fraction cases, valid/invalid constructor checks, and ordered conversion with hidden custom text, image blocks, excluded Bash and both summary types. Tests directly import the actual pinned `bashExecutionToText`; dates compare its constructors’ underlying Date.parse behavior for supported inputs. These are executed compatibility checks, not claimed proofs. The conversion assertions relevant to `suite/regressions/8537-custom-message-tool-result-ordering.test.ts` are represented by ordered typed conversion, but its agent-session integration remains pending. `custom-message.test.ts` tests terminal renderers and is not claimed ported here.

```sh
build/bend-native-toolchain/bend2/main.ts tests/messages.bend -o build/messages.js
sh scripts/build-pure.sh tests/messages.bend build/messages
python3 tests/messages_check.py --runner build/messages.js
python3 tests/messages_check.py --runner build/messages --threads 1
python3 tests/messages_check.py --runner build/messages --threads 4
```
