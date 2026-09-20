import Base
import ./provider-retry.bend as Retry
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-response-stream.bend as Stream
import ../../../runtime/src/http-response-metadata.bend as Metadata
import ../../../runtime/src/http-response-progress.bend as Progress
import ../../../runtime/src/http-body-consume.bend as Consume
import ../../../runtime/src/headers.bend as Headers
import ../../../runtime/src/record.bend as Record
import ../../../runtime/src/f64.bend as F

# A failed HTTP status retains both response metadata and the complete outcome
# of diagnostic-body consumption. Read/decoding/cleanup errors are not strings.
type Failure<-E: Data> is Data:
  StatusFailure{metadata: Metadata.Metadata, body: Result<&2, &2, Consume.TextError<E>, String>}

def rejected(-E: Data, -State: Type, metadata: Metadata.Metadata, body: Result<&2, &2, Consume.TextError<E>, String>) -> Result<&2, &1, Failure<E>, Response.Response<State>>:
  Fail{StatusFailure{metadata, body}}

def select(-E: Data, -State: Type, read: State -> IO(State & Result<&2, &2, E, Maybe<&2, Stream.Event>>), close: State -> IO(Result<&2, &2, E, Unit>), limit: Nat, metadata: Metadata.Metadata, body: Response.Body<State>, successful: Bool) -> IO(Result<&2, &1, Failure<E>, Response.Response<State>>):
  match successful:
    case True{}: IO.pure(Result<&2, &1, Failure<E>, Response.Response<State>>, Done{Response.Response{metadata, body}})
    case False{}:
      do IO<Result<&2, &1, Failure<E>, Response.Response<State>>>:
        diagnostic : Result<&2, &2, Consume.TextError<E>, String> <- Consume.textWith(E, State, read, close, limit, body)
        return rejected(E, State, metadata, diagnostic)

# Like a request with SDK retries disabled: return a successful response before
# reading its body; otherwise consume/close the error body before any retry.
# Streaming body-presence checks belong to the consumer, after this boundary.
def acceptWith(-E: Data, -State: Type, read: State -> IO(State & Result<&2, &2, E, Maybe<&2, Stream.Event>>), close: State -> IO(Result<&2, &2, E, Unit>), diagnosticLimit: Nat, response: Response.Response<State>) -> IO(Result<&2, &1, Failure<E>, Response.Response<State>>):
  match response:
    case Response.Response{+metadata, body}: select(E, State, read, close, diagnosticLimit, metadata, body, Metadata.ok(metadata))

# Keys are fixed, valid lower-case names. Use the same stored-value coalescing
# as Headers.get without inventing an impossible header-name failure path.
def retryFields(-E: Data, original: E, message: String, status: U32, headers: Headers.Headers) -> Retry.RequestFailure<E>:
  match headers:
    case Headers.Headers{+fields}:
      Retry.Provider{Retry.ProviderError{original, message, Some{F.fromU32(status)}, Headers.joined("x-should-retry", Record.get(List<&2, String>, fields, "x-should-retry")), Headers.joined("retry-after-ms", Record.get(List<&2, String>, fields, "retry-after-ms")), Headers.joined("retry-after", Record.get(List<&2, String>, fields, "retry-after"))}}

# The provider supplies its original typed error and rendering. This projects
# only transport metadata into the existing retry API; it does not format SDK
# errors or decide whether a diagnostic-body failure should be retryable.
def retryFailure(-E: Data, original: E, message: String, +metadata: Metadata.Metadata) -> Retry.RequestFailure<E>:
  retryFields(E, original, message, Metadata.status(metadata), Metadata.headers(metadata))
