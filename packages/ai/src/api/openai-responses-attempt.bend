import Base
import ./openai-responses-envelope.bend as Envelope
import ./openai-responses-fetch.bend as Fetch
import ./openai-http-error.bend as HTTPError
import ../utils/provider-http-response.bend as HTTP
import ../utils/provider-retry.bend as Retry
import ../../../runtime/src/http-fetch-scope.bend as Scope
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-response-stream.bend as Stream
import ../../../runtime/src/http-response-metadata.bend as Metadata
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/callback.bend as C

# The transport supplies this classification from its typed error. Configuration
# failures never become network retries merely because dispatch returned them.
type FetchCategory is Data:
  NonRetryable{}
  Connection{message: String}
  Timeout{}

type Error<-Reason: Data, -FetchError: Data, -ReadError: Data> is Data:
  FetchFailure{cause: Fetch.Error<Reason, FetchError>}
  HTTPFailure{cause: HTTPError.APIError}
  DiagnosticFailure{cause: HTTPError.ConstructionError<ReadError>}

def connection(-E: Data, original: E, message: String) -> Retry.RequestFailure<E>:
  Retry.Provider{Retry.ProviderError{original, message, None{}, None{}, None{}, None{}}}

def classified(-E: Data, original: E, category: FetchCategory) -> Retry.RequestFailure<E>:
  match category:
    case NonRetryable{}: Retry.Other{original}
    case Connection{message}: connection(E, original, message)
    case Timeout{}: connection(E, original, "Request timed out.")

def aborted(-Reason: Data, -E: Data, original: E, reason: Abort.AbortReason<Deadline.Cause<Reason>>) -> Retry.RequestFailure<E>:
  match reason:
    case Abort.Supplied{Deadline.Expired{}}: classified(E, original, Timeout{})
    case _: Retry.Other{original}

def dispatchAbort(-Reason: Data, -E: Data, original: E, category: FetchCategory, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> Retry.RequestFailure<E>:
  match reason:
    case None{}: classified(E, original, category)
    case Some{why}: aborted(Reason, E, original, why)

def dispatchCategory(-Reason: Data, -E: Data, original: E, category: FetchCategory, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> Retry.RequestFailure<E>:
  match category:
    case NonRetryable{}: Retry.Other{original}
    case other: dispatchAbort(Reason, E, original, other, reason)

def fetchFailure(-Reason: Data, -FetchError: Data, -ReadError: Data, categorize: FetchError -> FetchCategory, failure: Fetch.Error<Reason, FetchError>) -> Retry.RequestFailure<Error<Reason, FetchError, ReadError>>:
  match failure:
    case Fetch.InvalidTimeout{cause}: Retry.Other{FetchFailure{Fetch.InvalidTimeout{cause}}}
    case Fetch.FetchFailure{Scope.Aborted{+why}}:
      aborted(Reason, Error<Reason, FetchError, ReadError>, FetchFailure{Fetch.FetchFailure{Scope.Aborted{why}}}, why)
    case Fetch.FetchFailure{Scope.DispatchFailure{+cause, +why}}:
      dispatchCategory(Reason, Error<Reason, FetchError, ReadError>, FetchFailure{Fetch.FetchFailure{Scope.DispatchFailure{cause, why}}}, categorize(cause), why)

def diagnostic(-Reason: Data, -FetchError: Data, -ReadError: Data, failure: HTTPError.ConstructionError<ReadError>) -> Retry.RequestFailure<Error<Reason, FetchError, ReadError>>:
  match failure:
    case HTTPError.DiagnosticReadFailure{+metadata, cause}:
      HTTP.retryFailure(Error<Reason, FetchError, ReadError>, DiagnosticFailure{HTTPError.DiagnosticReadFailure{metadata, cause}}, "Could not read the error response diagnostic.", metadata)
    case HTTPError.DiagnosticEncodingFailure{+metadata, value}:
      HTTP.retryFailure(Error<Reason, FetchError, ReadError>, DiagnosticFailure{HTTPError.DiagnosticEncodingFailure{metadata, value}}, "Could not encode the error response diagnostic.", metadata)

def constructed(-Reason: Data, -FetchError: Data, -ReadError: Data, result: Result<&2, &2, HTTPError.ConstructionError<ReadError>, HTTPError.APIError>) -> Retry.RequestFailure<Error<Reason, FetchError, ReadError>>:
  match result:
    case Fail{cause}: diagnostic(Reason, FetchError, ReadError, cause)
    case Done{HTTPError.APIError{+metadata, value, +message}}:
      HTTP.retryFailure(Error<Reason, FetchError, ReadError>, HTTPFailure{HTTPError.APIError{metadata, value, message}}, message, metadata)

def accepted(-Reason: Data, -FetchError: Data, -ReadError: Data, -Transport: Type, result: Result<&2, &1, HTTP.Failure<ReadError>, Response.Response<Scope.State<Reason, Transport>>>) -> Result<&2, &1, Retry.RequestFailure<Error<Reason, FetchError, ReadError>>, Response.Response<Scope.State<Reason, Transport>>>:
  match result:
    case Fail{cause}: Fail{constructed(Reason, FetchError, ReadError, HTTPError.fromResponse(ReadError, cause))}
    case Done{response}: Done{response}

# Failed HTTP statuses consume and close their diagnostics before returning a
# retryable value. Successful responses transfer without reading their bodies.
def fetched(~Reason: Data, ~FetchError: Data, ~ReadError: Data, ~Transport: Type, ~read: Transport -> IO(Transport & Result<&2, &2, ReadError, Maybe<&2, Stream.Event>>), ~close: Transport -> IO(Result<&2, &2, ReadError, Unit>), categorize: FetchError -> FetchCategory, diagnosticLimit: Nat, result: Result<&2, &1, Fetch.Error<Reason, FetchError>, Response.Response<Scope.State<Reason, Transport>>>) -> IO(Result<&2, &1, Retry.RequestFailure<Error<Reason, FetchError, ReadError>>, Response.Response<Scope.State<Reason, Transport>>>):
  match result:
    case Fail{cause}: IO.pure(Result<&2, &1, Retry.RequestFailure<Error<Reason, FetchError, ReadError>>, Response.Response<Scope.State<Reason, Transport>>>, Fail{fetchFailure(Reason, FetchError, ReadError, categorize, cause)})
    case Done{response}:
      do IO<Result<&2, &1, Retry.RequestFailure<Error<Reason, FetchError, ReadError>>, Response.Response<Scope.State<Reason, Transport>>>>:
        result : Result<&2, &1, HTTP.Failure<ReadError>, Response.Response<Scope.State<Reason, Transport>>> <- HTTP.acceptWith(~ReadError, ~(Scope.State<Reason, Transport>), ~(state => Scope.read(Reason, ReadError, Transport, read, state)), ~(state => Scope.close(Reason, ReadError, Transport, close, state)), diagnosticLimit, response)
        return accepted(Reason, FetchError, ReadError, Transport, result)

def run(~Reason: Data, ~FetchError: Data, ~ReadError: Data, ~Transport: Type, ~read: Transport -> IO(Transport & Result<&2, &2, ReadError, Maybe<&2, Stream.Event>>), ~close: Transport -> IO(Result<&2, &2, ReadError, Unit>), request: Envelope.Request, parent: Abort.AbortSignal<Reason>, fetch: C.Callback<Fetch.Input<Reason>, Result<&2, &1, FetchError, Response.Response<Transport>>>, categorize: FetchError -> FetchCategory, diagnosticLimit: Nat) -> IO(Result<&2, &1, Retry.RequestFailure<Error<Reason, FetchError, ReadError>>, Response.Response<Scope.State<Reason, Transport>>>):
  do IO<Result<&2, &1, Retry.RequestFailure<Error<Reason, FetchError, ReadError>>, Response.Response<Scope.State<Reason, Transport>>>>:
    result : Result<&2, &1, Fetch.Error<Reason, FetchError>, Response.Response<Scope.State<Reason, Transport>>> <- Fetch.run(Reason, FetchError, Transport, request, parent, fetch)
    fetched(~Reason, ~FetchError, ~ReadError, ~Transport, ~read, ~close, categorize, diagnosticLimit, result)
