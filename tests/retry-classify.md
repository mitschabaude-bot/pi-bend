# Retry classification and context overflow

`packages/ai/src/utils/retry.bend` is upstream `retry.ts`'s transient-error classifier (`isRetryableAssistantError`: a finished assistant message with an error message that matches none of the account-limit patterns and one of the retryable provider/transport patterns) and agent retry policy (`RetryPolicy`, `retryDelayMs`: `baseDelayMs * 2^(attempt-1)`, clamped to JavaScript's safe-integer range, capped by `maxAgentDelayMs` or sixty seconds). `packages/ai/src/utils/overflow.bend` is `overflow.ts` (`isContextOverflow`: provider error text, silent overflow above the window on a normal stop, and zero-output length stops filling 99% of the window; `isRecoverableLength`). Upstream's alternation regexes are lists of one pattern each, compiled case-insensitively by `runtime/regex.bend` and tried in order.

`tests/retry-classify.bend` classifies JSON cases (error message, stop reason, usage, context window, desired output limit, delay policy and attempt) and `tests/retry_classify_check.py` compares every answer with the pinned `retry.ts`/`overflow.ts` through `tests/retry_classify_reference.ts`. The corpus holds every message of upstream's `retry.test.ts` and `overflow.test.ts` (classification and `retryDelayMs` cases), the documented provider overflow messages, near misses for each pattern, usage-based overflow and recoverable-length shapes; 158 cases agree on Bun and native one/four threads. `retryAssistantCall` (the summarization retry loop) is not ported yet; it follows with compaction.

## Adaptations

- Upstream's `contextWindow?: number` is a plain `F64` where zero means unknown; both disable the usage checks.
- `retryDelayMs` takes the policy fields directly (`baseDelayMs`, optional `maxAgentDelayMs`); `policyDelayMs` reads them from a `RetryPolicy`.
- The unpatched Bun lane overflows its stack when the whole 40 KB case file is read at once ([BEND-019](../docs/bend-issues.md)), so the check feeds it sixteen cases per process; the native binary reads the file whole.

```sh
bun build/bend-process-files/bend2/main.ts tests/retry-classify.bend -o build/retry-classify.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=4 sh scripts/build-pure.sh tests/retry-classify.bend build/retry-classify
python3 tests/retry_classify_check.py --runner build/retry-classify.js
python3 tests/retry_classify_check.py --runner build/retry-classify --threads 4
```
