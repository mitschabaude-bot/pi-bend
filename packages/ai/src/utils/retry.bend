import Base
import ../types.bend as T
import ../../../runtime/src/regex.bend as Regex
import ../../../runtime/src/f64.bend as F

# pi `retry.ts`: the transient-error classifier for finished assistant
# messages and the agent-level retry policy (bounded attempts, exponential
# backoff capped per attempt). The patterns are upstream's alternations,
# one entry each, matched case-insensitively. `retryAssistantCall` (the
# summarization retry loop) follows with compaction.

# Subscription, quota and billing limits are account limits, not throttles.
def nonRetryableLimitPatterns() -> List<&2, String>:
  "GoUsageLimitError" <> "FreeUsageLimitError" <> "Monthly usage limit reached" <> "available balance" <> "insufficient_quota" <> "out of budget" <> "quota exceeded" <> "billing" <> Nil{}

def retryablePatterns() -> List<&2, String>:
  # Generic provider load, HTTP status, and server-side transient failures.
  "overloaded" <> "currently experiencing high demand" <> "rate.?limit" <> "too many requests" <> "429" <> "500" <> "502" <> "503" <> "504" <> "520" <> "524" <> "service.?unavailable" <> "server.?error" <> "internal.?error" <>
  # Wrapper/provider text for transient upstream failures.
  "provider.?returned.?error" <> "exceeded request buffer limit while retrying upstream" <>
  # Network, proxy, and fetch transport failures.
  "network.?error" <> "connection.?error" <> "connection.?refused" <> "connection.?lost" <> "other side closed" <> "fetch failed" <> "getaddrinfo" <> "ENOTFOUND" <> "EAI_AGAIN" <> "upstream.?connect" <> "reset before headers" <> "socket hang up" <> "socket connection was closed" <> "timed? out" <> "timeout" <> "terminated" <>
  # WebSocket transports report close/error text instead of HTTP text.
  "websocket.?closed" <> "websocket.?error" <>
  # Premature stream endings from SDKs and transports.
  "ended without" <> "stream ended before message_stop" <> "stream ended before a terminal response event" <> "http2 request did not get a response" <>
  # Provider-requested retry delay cap failures flow through this policy.
  "retry delay" <>
  # Explicit retry guidance emitted mid-stream.
  "you can retry your request" <> "try your request again" <> "please retry your request" <>
  # gRPC based providers.
  "ResourceExhausted" <> Nil{}

def matched(compiled: Result<&2, &2, Regex.Error, Regex.Regex>, text: String) -> Bool:
  match compiled:
    case Done{regex}: Regex.isMatch(regex, text)
    case Fail{_}: False{}

# True when any pattern matches, stopping at the first match.
def matchesAny(patterns: List<&2, String>, +text: String) -> Bool:
  match patterns:
    case Nil{}: False{}
    case pattern <> rest: Bool.pick(Unit -> Bool, matched(Regex.compile(pattern, True{}), text), _ => True{}, _ => matchesAny(rest, text))(Unit{})

def retryableText(+text: String) -> Bool:
  Bool.pick(Unit -> Bool, Bool.or(String.eq(text, ""), matchesAny(nonRetryableLimitPatterns(), text)), _ => False{}, _ => matchesAny(retryablePatterns(), text))(Unit{})

def retryableError(stopReason: T.StopReason, errorMessage: Maybe<&2, String>) -> Bool:
  match stopReason errorMessage:
    case T.Error{} Some{text}: retryableText(text)
    case _ _: False{}

# Whether a failed assistant message looks like a transient provider or
# transport error. Callers handle context overflow first, then apply their
# own budget, backoff and reporting.
def isRetryableAssistantError(-Arguments: Data, -DiagnosticDetails: Data, message: T.AssistantMessage<Arguments, DiagnosticDetails>) -> Bool:
  match message:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, stopReason, _, errorMessage, _, _, _}: retryableError(stopReason, errorMessage)

# Policy
# ------
# Bounded attempts with exponential backoff `baseDelayMs * 2^(attempt-1)`;
# `maxAgentDelayMs` caps each delay and defaults to 60 seconds.

type RetryPolicy is Data:
  RetryPolicy{enabled: Bool, maxRetries: Nat, baseDelayMs: F64, maxAgentDelayMs: Maybe<&2, F64>}

def DEFAULT_MAX_AGENT_RETRY_DELAY_MS() -> F64: F.fromU32(60000)

def doubled(times: Nat, +value: F64) -> F64:
  match times:
    case 0n: value
    case 1n+rest: doubled(rest, F.multiply(value, F.fromU32(2)))

def MAX_SAFE_INTEGER() -> F64: F.subtract(doubled(53n, F.fromU32(1)), F.fromU32(1))

# JavaScript's Number.isSafeInteger: an integer of magnitude at most 2^53 - 1.
def safeInteger(+value: F64) -> Bool:
  Bool.and(F.isInteger(value), Bool.and(F.isAtMost(F.compare(value, MAX_SAFE_INTEGER())), F.isAtLeast(F.compare(value, F.negate(MAX_SAFE_INTEGER())))))

def safeDelay(+delay: F64) -> F64:
  Bool.pick(F64, safeInteger(delay), delay, MAX_SAFE_INTEGER())

def retryDelayMs(baseDelayMs: F64, maxAgentDelayMs: Maybe<&2, F64>, attempt: Nat) -> F64:
  F.minimum(safeDelay(doubled(Nat.sub(attempt, 1n), baseDelayMs)), Maybe.default(&2, F64, maxAgentDelayMs, DEFAULT_MAX_AGENT_RETRY_DELAY_MS()))

def policyDelayMs(policy: RetryPolicy, attempt: Nat) -> F64:
  match policy:
    case RetryPolicy{_, _, baseDelayMs, maxAgentDelayMs}: retryDelayMs(baseDelayMs, maxAgentDelayMs, attempt)
