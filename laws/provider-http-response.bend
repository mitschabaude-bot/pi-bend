import Base
import ../packages/ai/src/utils/provider-http-response.bend as Provider
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-stream.bend as Stream
import ../packages/runtime/src/http-response-metadata.bend as Metadata
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/http-body-consume.bend as Consume
import ../packages/runtime/src/http-head.bend as Head
import ../packages/runtime/src/http-status.bend as Status
import ../packages/runtime/src/http-header.bend as Header
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/f64.bend as F

# Any successful metadata predicate hands off any affine body unchanged,
# without invoking either transport function or applying the diagnostic cap.
law accepted_owner_has_no_body_io:
  for -E: Data
  for -State: Type
  for read: State -> IO(State & Result<&2, &2, E, Maybe<&2, Stream.Event>>)
  for close: State -> IO(Result<&2, &2, E, Unit>)
  for limit: Nat
  for metadata: Metadata.Metadata
  for body: Response.Body<State>
  for accepted: {Metadata.ok(metadata) == True{} : Bool}
  {Provider.acceptWith(E, State, read, close, limit, Response.Response{metadata, body}) == IO.pure(Result<&2, &1, Provider.Failure<E>, Response.Response<State>>, Done{Response.Response{metadata, body}}) : IO(Result<&2, &1, Provider.Failure<E>, Response.Response<State>>)}

# A failed status runs the owned consumer before producing its typed failure.
# This is sequencing of IO programs, not a termination claim about the source.
law rejected_owner_runs_diagnostic_first:
  for -E: Data
  for -State: Type
  for read: State -> IO(State & Result<&2, &2, E, Maybe<&2, Stream.Event>>)
  for close: State -> IO(Result<&2, &2, E, Unit>)
  for limit: Nat
  for metadata: Metadata.Metadata
  for body: Response.Body<State>
  for rejected: {Metadata.ok(metadata) == False{} : Bool}
  {Provider.acceptWith(E, State, read, close, limit, Response.Response{metadata, body}) == IO.bind(Result<&2, &2, Consume.TextError<E>, String>, Result<&2, &1, Provider.Failure<E>, Response.Response<State>>, Consume.textWith(E, State, read, close, limit, body), diagnostic => IO.pure(Result<&2, &1, Provider.Failure<E>, Response.Response<State>>, Fail{Provider.StatusFailure{metadata, diagnostic}})) : IO(Result<&2, &1, Provider.Failure<E>, Response.Response<State>>)}

law rejected_diagnostic_is_preserved:
  for -E: Data
  for -State: Type
  for metadata: Metadata.Metadata
  for body: Result<&2, &2, Consume.TextError<E>, String>
  {Provider.rejected(E, State, metadata, body) == Fail{Provider.StatusFailure{metadata, body}} : Result<&2, &1, Provider.Failure<E>, Response.Response<State>>}

# Arbitrary original errors and rendered messages survive, status comes from
# the response head, and retry hints use normal Headers value coalescing.
law retry_metadata_projection:
  for -E: Data
  for original: E
  for message: String
  for major: U32
  for minor: U32
  for status: U32
  for reason: List<&2, U32>
  for raw: List<&2, Header.Header>
  for fields: Record.Record<List<&2, String>>
  for expose: Bool
  {Provider.retryFailure(E, original, message, Metadata.Metadata{Head.ResponseHead{Status.StatusLine{major, minor, status, reason}, raw}, Headers.Headers{fields}, expose}) == Retry.Provider{Retry.ProviderError{original, message, Some{F.fromU32(status)}, Headers.joined("x-should-retry", Record.get(List<&2, String>, fields, "x-should-retry")), Headers.joined("retry-after-ms", Record.get(List<&2, String>, fields, "retry-after-ms")), Headers.joined("retry-after", Record.get(List<&2, String>, fields, "retry-after"))}} : Retry.RequestFailure<E>}
