import Base
import ../types.bend as T
import ./openai-responses-prepare.bend as Preparation
import ./openai-responses-native-session.bend as Native
import ./openai-responses-native-session-error.bend as Errors
import ./openai-responses-configured-acquire.bend as Acquire
import ./openai-responses-envelope.bend as Envelope
import ./openai-request-headers.bend as Headers
import ../../../runtime/src/url-absolute.bend as URL
import ../../../runtime/src/f64.bend as F
import ../utils/provider-request.bend as Request
import ../utils/provider-retry.bend as Retry
import ../utils/provider-retry-config.bend as Config
import ../utils/provider-retry-options.bend as RetryOptions
import ../utils/provider-hook-options.bend as HookOptions
import ../utils/provider-hook-map.bend as Hooks
import ../../../runtime/src/abort.bend as Abort

# Retain the original preparation for processing. Only the outgoing payload
# changes; the payload hook is removed from the subsequent acquisition path.
type Plan<-Reason: Data, -Source: Data, -Hook: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Plan{original: Preparation.Prepared, payload: T.JsonValue, options: Native.Options(Reason, Source, Hook, Telemetry, Fetch), retry: Retry.ProviderRetryOptions<Reason>}

def withoutPayload(-Reason: Data, -Source: Data, -Hook: Data, -Telemetry: Data, -Fetch: Data, +options: Native.Options(Reason, Source, Hook, Telemetry, Fetch)) -> Native.Options(Reason, Source, Hook, Telemetry, Fetch):
  match options:
    case T.ProviderRequestOptions{_, _, _, _, _, _, response, _, _, _, _}:
      HookOptions.replace(T.JsonValue, T.Model<T.JsonValue>, Abort.AbortSignal<Reason>, Telemetry, Fetch, Errors.Error<Reason, Source, Hook>, Errors.Error<Reason, Source, Hook>, options, Hooks.Hooks{None{}, response})

def selected(-Reason: Data, -Source: Data, -Hook: Data, -Telemetry: Data, -Fetch: Data, original: Preparation.Prepared, options: Native.Options(Reason, Source, Hook, Telemetry, Fetch), retry: Retry.ProviderRetryOptions<Reason>, result: Result<&2, &2, Request.Error<Errors.Error<Reason, Source, Hook>>, T.JsonValue>) -> Result<&2, &2, Errors.Error<Reason, Source, Hook>, Plan<Reason, Source, Hook, Telemetry, Fetch>>:
  match result:
    case Fail{cause}: Fail{Errors.AcquisitionFailure{Acquire.AcquisitionFailed{cause}}}
    case Done{payload}: Done{Plan{original, payload, withoutPayload(Reason, Source, Hook, Telemetry, Fetch, options), retry}}

def payload(value: Preparation.Prepared) -> T.JsonValue:
  match value:
    case Preparation.Prepared{_, _, _, value, _, _, _}: value

def validated(-Reason: Data, -Source: Data, -Hook: Data, -Telemetry: Data, -Fetch: Data, model: T.Model<T.JsonValue>, +original: Preparation.Prepared, +options: Native.Options(Reason, Source, Hook, Telemetry, Fetch), result: Result<&2, &2, RetryOptions.Error, Retry.ProviderRetryOptions<Reason>>) -> IO(Result<&2, &2, Errors.Error<Reason, Source, Hook>, Plan<Reason, Source, Hook, Telemetry, Fetch>>):
  match options result:
    case _ Fail{cause}:
      IO.pure(Result<&2, &2, Errors.Error<Reason, Source, Hook>, Plan<Reason, Source, Hook, Telemetry, Fetch>>, Fail{Errors.AcquisitionFailure{Acquire.InvalidOptions{cause}}})
    case T.ProviderRequestOptions{_, _, _, _, _, hook, _, _, _, _, _} Done{retry}:
      do IO<Result<&2, &2, Errors.Error<Reason, Source, Hook>, Plan<Reason, Source, Hook, Telemetry, Fetch>>>:
        value : Result<&2, &2, Request.Error<Errors.Error<Reason, Source, Hook>>, T.JsonValue> <- Request.payload(T.JsonValue, T.Model<T.JsonValue>, Errors.Error<Reason, Source, Hook>, payload(original), model, hook)
        return selected(Reason, Source, Hook, Telemetry, Fetch, original, options, retry, value)

def prepare(-Reason: Data, -Source: Data, -Hook: Data, -Telemetry: Data, -Fetch: Data, model: T.Model<T.JsonValue>, original: Preparation.Prepared, +options: Native.Options(Reason, Source, Hook, Telemetry, Fetch)) -> IO(Result<&2, &2, Errors.Error<Reason, Source, Hook>, Plan<Reason, Source, Hook, Telemetry, Fetch>>):
  validated(Reason, Source, Hook, Telemetry, Fetch, model, original, options, Config.request(T.Model<T.JsonValue>, Reason, Telemetry, Fetch, T.JsonValue, Errors.Error<Reason, Source, Hook>, options))

# A complete wire request is validated and serialized before any system runtime
# is initialized. Retry attempts reuse it; processing retains the original
# preparation, including grammar metadata unrelated to a hook replacement.
type Wire<-Reason: Data, -Source: Data, -Hook: Data> is Data:
  Wire{original: Preparation.Prepared, request: Envelope.Request, response: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, Errors.Error<Reason, Source, Hook>)>, retry: Retry.ProviderRetryOptions<Reason>}

# The provider retry wrapper gives an observed cancellation precedence over a
# failed attempt, including a locally rejected envelope. No retry effects are
# required for this non-retryable failure.
def rejected(-Reason: Data, -Source: Data, -Hook: Data, cause: Envelope.Error, aborted: Bool) -> Errors.Error<Reason, Source, Hook>:
  match aborted:
    case True{}: Errors.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestAborted{}}}}
    case False{}: Errors.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestFailed{Retry.Other{Errors.EnvelopeFailure{cause}}}}}}

def checked(-Reason: Data, -Source: Data, -Hook: Data, original: Preparation.Prepared, response: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, Errors.Error<Reason, Source, Hook>)>, retry: Retry.ProviderRetryOptions<Reason>, aborted: Bool, result: Result<&2, &2, Envelope.Error, Envelope.Request>) -> Result<&2, &2, Errors.Error<Reason, Source, Hook>, Wire<Reason, Source, Hook>>:
  match aborted result:
    case True{} _: Fail{Errors.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestAborted{}}}}}
    case False{} Fail{cause}: Fail{rejected(Reason, Source, Hook, cause, False{})}
    case False{} Done{request}: Done{Wire{original, request, response, retry}}

# Like the SDK, inspect cancellation after building the request and before
# fetch. This also prevents system configuration errors masking an abort.
def encoded(-Reason: Data, -Source: Data, -Hook: Data, original: Preparation.Prepared, response: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, Errors.Error<Reason, Source, Hook>)>, +retry: Retry.ProviderRetryOptions<Reason>, result: Result<&2, &2, Envelope.Error, Envelope.Request>) -> IO(Result<&2, &2, Errors.Error<Reason, Source, Hook>, Wire<Reason, Source, Hook>>):
  match retry:
    case Retry.ProviderRetryOptions{_, _, signal}:
      do IO<Result<&2, &2, Errors.Error<Reason, Source, Hook>, Wire<Reason, Source, Hook>>>:
        aborted : Bool <- Retry.signalAborted(Reason, signal)
        return checked(Reason, Source, Hook, original, response, retry, aborted, result)

def wireRequest(url: URL.Context, headers: Headers.Defaults, original: Preparation.Prepared, timeout: Maybe<&2, F.F64>, chosen: T.JsonValue) -> Result<&2, &2, Envelope.Error, Envelope.Request>:
  match original:
    case Preparation.Prepared{key, baseUrl, fields, _, _, _, _}: Envelope.prepare(url, headers, key, fields, baseUrl, timeout, chosen)

def seal(-Reason: Data, -Source: Data, -Hook: Data, -Telemetry: Data, -Fetch: Data, url: URL.Context, headers: Headers.Defaults, result: Result<&2, &2, Errors.Error<Reason, Source, Hook>, Plan<Reason, Source, Hook, Telemetry, Fetch>>) -> IO(Result<&2, &2, Errors.Error<Reason, Source, Hook>, Wire<Reason, Source, Hook>>):
  match result:
    case Fail{cause}: IO.pure(Result<&2, &2, Errors.Error<Reason, Source, Hook>, Wire<Reason, Source, Hook>>, Fail{cause})
    case Done{Plan{+original, chosen, T.ProviderRequestOptions{_, _, _, _, _, _, response, _, timeout, _, _}, retry}}:
      encoded(Reason, Source, Hook, original, response, retry, wireRequest(url, headers, original, timeout, chosen))
