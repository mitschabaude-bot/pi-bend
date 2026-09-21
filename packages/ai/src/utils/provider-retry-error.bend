import Base
import ./provider-retry.bend as R
import ./provider-retry-policy.bend as P
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/f64-round.bend as Round
import ../../../runtime/src/f64-decimal.bend as Decimal

type RenderedError is Data:
  RenderedError{name: String, message: String}

type FormattingError is Data:
  NumberFormattingFailure{}

def createAbortError() -> RenderedError:
  RenderedError{"AbortError", "Request aborted"}

def message(delay: Maybe<&2, String>, maximum: Maybe<&2, String>, providerMessage: String) -> Result<&2, &2, FormattingError, RenderedError>:
  match delay maximum:
    case Some{seconds} Some{limit}: Done{RenderedError{"Error", "Server requested " ++ seconds ++ "s retry delay (max: " ++ limit ++ "s). " ++ providerMessage}}
    case _ _: Fail{NumberFormattingFailure{}}

def delayError(error: P.DelayError, providerMessage: String) -> Result<&2, &2, FormattingError, RenderedError>:
  match error:
    case P.ServerDelayTooLong{delay, maximum}:
      message(Decimal.toDecimal(Round.ceil(F.divide(delay, F.fromU32(1000)))), Decimal.toDecimal(Round.ceil(F.divide(maximum, F.fromU32(1000)))), providerMessage)

def original(-E: Data, error: R.RequestFailure<E>) -> E:
  match error:
    case R.Other{value}: value
    case R.Provider{R.ProviderError{value, _, _, _, _, _}}: value

# Original request errors retain the provider's own rendering. Only errors
# introduced by the retry helper acquire the names/messages defined here.
def render(-E: Data, error: R.RetryFailure<E>, renderOriginal: E -> RenderedError) -> Result<&2, &2, FormattingError, RenderedError>:
  match error:
    case R.RequestFailed{failure}: Done{renderOriginal(original(E, failure))}
    case R.SleepRejected{_}: Done{RenderedError{"InvalidRetryDelay", "Retry delay is outside the native timer range"}}
    case R.RequestAborted{}: Done{createAbortError()}
    case R.DelayRejected{failure, providerMessage}: delayError(failure, providerMessage)
