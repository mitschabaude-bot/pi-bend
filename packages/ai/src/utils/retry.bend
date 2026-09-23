import Base
import ../types.bend as T
import ./provider-retry.bend as ProviderRetry
import ../../../runtime/src/abort.bend as A
import ../../../runtime/src/callback.bend as C
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

# Retried calls
# -------------
# upstream RetryCallbacks: one callback receives the three notices.

type RetryNotice is Data:
  RetryScheduled{attempt: Nat, maxAttempts: Nat, delayMs: F64, errorMessage: String}
  RetryAttemptStart{}
  RetryFinished{success: Bool, attempt: Nat, finalError: Maybe<&2, String>}

def RetryCallbacks() -> Data: C.Callback<RetryNotice, Unit>

def notify(callbacks: Maybe<&2, RetryCallbacks()>, notice: RetryNotice) -> IO(Unit):
  match callbacks:
    case None{}: IO.pure(Unit, Unit{})
    case Some{callback}: C.call(RetryNotice, Unit, callback, notice)

type LastRetry is Data:
  LastRetry{attempt: Nat, errorMessage: String}

def finishedNotice(last: Maybe<&2, LastRetry>, success: Bool, finalError: Maybe<&2, String>) -> Maybe<&2, RetryNotice>:
  match last:
    case None{}: None{}
    case Some{LastRetry{attempt, _}}: Some{RetryFinished{success, attempt, finalError}}

def notifyMaybe(callbacks: Maybe<&2, RetryCallbacks()>, notice: Maybe<&2, RetryNotice>) -> IO(Unit):
  match notice:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}: notify(callbacks, value)

def maxAttemptsOf(policy: Maybe<&2, RetryPolicy>) -> Nat:
  match policy:
    case Some{RetryPolicy{True{}, maxRetries, _, _}}: maxRetries
    case _: 0n

def delayOf(policy: Maybe<&2, RetryPolicy>, attempt: Nat) -> F64:
  match policy:
    case Some{value}: policyDelayMs(value, attempt)
    case None{}: F.fromU32(0)

def errorTextOf(errorMessage: Maybe<&2, String>) -> String:
  match errorMessage:
    case Some{SNil{}}: "Unknown error"
    case Some{text}: text
    case None{}: "Unknown error"

# An aborted backoff returns the failed response marked aborted, without its error text.
def abortedResponse(-Arguments: Data, -DiagnosticDetails: Data, message: T.AssistantMessage<Arguments, DiagnosticDetails>) -> T.AssistantMessage<Arguments, DiagnosticDetails>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, providerThinkingLevel, diagnostics, usage, _, deferred, _, rawStopReason, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, providerThinkingLevel, diagnostics, usage, T.Aborted{}, deferred, None{}, rawStopReason, endTurn, timestamp}

# The loop's states: call the producer, sleep before a retry, resume after
# the sleep, or settle with the response.
type Loop<-Arguments: Data, -DiagnosticDetails: Data> is Data:
  Call{attempt: Nat, last: Maybe<&2, LastRetry>}
  Backoff{attempt: Nat, errorMessage: String, response: T.AssistantMessage<Arguments, DiagnosticDetails>}
  Resume{attempt: Nat, errorMessage: String}
  Settled{response: T.AssistantMessage<Arguments, DiagnosticDetails>, notice: Maybe<&2, RetryNotice>}

def decideAfter(-Arguments: Data, -DiagnosticDetails: Data, +response: T.AssistantMessage<Arguments, DiagnosticDetails>, +attempt: Nat, +last: Maybe<&2, LastRetry>, maxAttempts: Nat, stopReason: T.StopReason, +errorMessage: Maybe<&2, String>, retryable: Bool) -> Loop<Arguments, DiagnosticDetails>:
  match stopReason:
    case T.Aborted{}: Settled{response, finishedNotice(last, False{}, None{})}
    case T.Error{}: Bool.pick(Loop<Arguments, DiagnosticDetails>, Bool.or(Bool.not(Nat.is_lt(attempt, maxAttempts)), Bool.not(retryable)), Settled{response, finishedNotice(last, False{}, errorMessage)}, Backoff{Nat.add(attempt, 1n), errorTextOf(errorMessage), response})
    case _: Settled{response, finishedNotice(last, True{}, None{})}

def afterResponse(-Arguments: Data, -DiagnosticDetails: Data, +response: T.AssistantMessage<Arguments, DiagnosticDetails>, attempt: Nat, last: Maybe<&2, LastRetry>, maxAttempts: Nat) -> Loop<Arguments, DiagnosticDetails>:
  decideAfter(Arguments, DiagnosticDetails, response, attempt, last, maxAttempts, T.assistantStopReason(Arguments, DiagnosticDetails, response), T.assistantErrorMessage(Arguments, DiagnosticDetails, response), isRetryableAssistantError(Arguments, DiagnosticDetails, response))

def afterSleep(-Arguments: Data, -DiagnosticDetails: Data, slept: Result<&2, &2, ProviderRetry.SleepError, Unit>, attempt: Nat, errorMessage: String, response: T.AssistantMessage<Arguments, DiagnosticDetails>) -> Loop<Arguments, DiagnosticDetails>:
  match slept:
    case Done{_}: Resume{attempt, errorMessage}
    case Fail{_}: Settled{abortedResponse(Arguments, DiagnosticDetails, response), Some{RetryFinished{False{}, attempt, Some{errorMessage}}}}

def retryStep(~Arguments: Data, ~DiagnosticDetails: Data, ~Env: Data, ~produce: Env -> IO(T.AssistantMessage<Arguments, DiagnosticDetails>), fuel: Nat, +env: Env, +policy: Maybe<&2, RetryPolicy>, +signal: Maybe<&2, A.AbortSignal<Unit>>, +callbacks: Maybe<&2, RetryCallbacks()>, state: Loop<Arguments, DiagnosticDetails>) -> IO(T.AssistantMessage<Arguments, DiagnosticDetails>):
  match fuel state:
    case _ Settled{response, notice}:
      do IO<T.AssistantMessage<Arguments, DiagnosticDetails>>:
        notifyMaybe(callbacks, notice)
        return response
    case 0n Call{_, _}: produce(env)
    case 0n Backoff{_, _, response}: IO.pure(T.AssistantMessage<Arguments, DiagnosticDetails>, response)
    case 0n Resume{_, _}: produce(env)
    case 1n+rest Call{attempt, last}:
      do IO<T.AssistantMessage<Arguments, DiagnosticDetails>>:
        response : T.AssistantMessage<Arguments, DiagnosticDetails> <- produce(env)
        retryStep(~Arguments, ~DiagnosticDetails, ~Env, ~produce, rest, env, policy, signal, callbacks, afterResponse(Arguments, DiagnosticDetails, response, attempt, last, maxAttemptsOf(policy)))
    case 1n+rest Backoff{+attempt, +errorMessage, response}:
      do IO<T.AssistantMessage<Arguments, DiagnosticDetails>>:
        notify(callbacks, RetryScheduled{attempt, maxAttemptsOf(policy), delayOf(policy, attempt), errorMessage})
        slept : Result<&2, &2, ProviderRetry.SleepError, Unit> <- ProviderRetry.sleep(Unit, ProviderRetry.SleepInput{delayOf(policy, attempt), signal})
        retryStep(~Arguments, ~DiagnosticDetails, ~Env, ~produce, rest, env, policy, signal, callbacks, afterSleep(Arguments, DiagnosticDetails, slept, attempt, errorMessage, response))
    case 1n+rest Resume{+attempt, errorMessage}:
      do IO<T.AssistantMessage<Arguments, DiagnosticDetails>>:
        notify(callbacks, RetryAttemptStart{})
        retryStep(~Arguments, ~DiagnosticDetails, ~Env, ~produce, rest, env, policy, signal, callbacks, Call{attempt, Some{LastRetry{attempt, errorMessage}}})

# upstream retryAssistantCall: produce until a non-retryable outcome or the
# policy's attempts are spent; an aborted backoff returns an aborted message.
def retryAssistantCall(~Arguments: Data, ~DiagnosticDetails: Data, ~Env: Data, ~produce: Env -> IO(T.AssistantMessage<Arguments, DiagnosticDetails>), env: Env, +policy: Maybe<&2, RetryPolicy>, signal: Maybe<&2, A.AbortSignal<Unit>>, callbacks: Maybe<&2, RetryCallbacks()>) -> IO(T.AssistantMessage<Arguments, DiagnosticDetails>):
  retryStep(~Arguments, ~DiagnosticDetails, ~Env, ~produce, Nat.add(Nat.mul(3n, maxAttemptsOf(policy)), 3n), env, policy, signal, callbacks, Call{0n, None{}})
