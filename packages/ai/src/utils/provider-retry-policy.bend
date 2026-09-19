import Base
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/parse-float.bend as Number

# Provider adapters supply normalized header values and optional status. Plain
# application failures never enter this policy; no SDK object reflection.
type DelaySource is Data:
  Backoff{}
  ServerMilliseconds{value: F.F64}
  ServerDate{text: String}

type DelayError is Data:
  ServerDelayTooLong{delayMs: F.F64, maxDelayMs: F.F64}

def DEFAULT_MAX_RETRY_DELAY_MS() -> F.F64: F.fromU32(60000)

def atLeast500(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case Some{GT{}}: True{}
    case _: False{}

def equalOrder(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case _: False{}

def equal(left: F.F64, right: F.F64) -> Bool: equalOrder(F.compare(left, right))

def retryableStatus(status: Maybe<&2, F.F64>) -> Bool:
  match status:
    case None{}: True{}
    case Some{+value}: equal(value, F.fromU32(408)) || equal(value, F.fromU32(409)) || equal(value, F.fromU32(429)) || atLeast500(F.compare(value, F.fromU32(500)))

def isRetryableProviderError(status: Maybe<&2, F.F64>, shouldRetry: Maybe<&2, String>) -> Bool:
  match shouldRetry:
    case Some{"true"}: True{}
    case Some{"false"}: False{}
    case _: retryableStatus(status)

def secondsOrDate(invalid: Bool, seconds: F.F64, text: String) -> DelaySource:
  match invalid:
    case True{}: ServerDate{text}
    case False{}: ServerMilliseconds{F.multiply(seconds, F.fromU32(1000))}

def retryAfter(value: Maybe<&2, String>) -> DelaySource:
  match value:
    case None{}: Backoff{}
    case Some{SNil{}}: Backoff{}
    case Some{+text}:
      +seconds = Number.parseFloat(text)
      secondsOrDate(F.isNaN(seconds), seconds, text)

def millisecondsOrFallback(invalid: Bool, value: F.F64, fallback: Maybe<&2, String>) -> DelaySource:
  match invalid:
    case True{}: retryAfter(fallback)
    case False{}: ServerMilliseconds{value}

def selectDelaySource(milliseconds: Maybe<&2, String>, seconds: Maybe<&2, String>) -> DelaySource:
  match milliseconds:
    case None{}: retryAfter(seconds)
    case Some{SNil{}}: retryAfter(seconds)
    case Some{text}:
      +value = Number.parseFloat(text)
      millisecondsOrFallback(F.isNaN(value), value, seconds)

def positive(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{GT{}}: True{}
    case _: False{}

def maxDelay(value: Maybe<&2, F.F64>) -> F.F64:
  match value:
    case None{}: DEFAULT_MAX_RETRY_DELAY_MS()
    case Some{scalar}: scalar

def limited(excessive: Bool, delayMs: F.F64, maxDelayMs: F.F64) -> Result<&2, &2, DelayError, F.F64>:
  match excessive:
    case True{}: Fail{ServerDelayTooLong{delayMs, maxDelayMs}}
    case False{}: Done{delayMs}

def validateServerRetryDelayMs(+delayMs: F.F64, maximum: Maybe<&2, F.F64>) -> Result<&2, &2, DelayError, F.F64>:
  +limit = maxDelay(maximum)
  limited(positive(F.compare(limit, F.fromU32(0))) && positive(F.compare(delayMs, limit)), delayMs, limit)

def baseDelay(index: Nat) -> F.F64:
  match index:
    case 0n: F.fromU32(500)
    case 1n: F.fromU32(1000)
    case 2n: F.fromU32(2000)
    case 3n: F.fromU32(4000)
    case _: F.fromU32(8000)

def backoffDelay(retryIndex: Nat, random: F.F64) -> F.F64:
  F.multiply(baseDelay(retryIndex), F.subtract(F.fromU32(1), F.multiply(random, F.divide(F.fromU32(1), F.fromU32(4)))))

# Date parsing, current time and randomness are explicit effects of the driver.
# A date instruction must be resolved before validating its server delay;
# backoff jitter is not subject to the server-requested-delay cap.
def resolveServerDate(parsedEpochMs: F.F64, nowMs: F.F64, maximum: Maybe<&2, F.F64>) -> Result<&2, &2, DelayError, F.F64>:
  validateServerRetryDelayMs(F.subtract(parsedEpochMs, nowMs), maximum)
