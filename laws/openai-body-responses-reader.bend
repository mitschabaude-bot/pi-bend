import Base
import ../packages/ai/src/api/openai-body-responses-reader.bend as Body
import ../packages/ai/src/api/openai-responses-reader.bend as Reader
import ../packages/ai/src/api/openai-sse-reader.bend as SSE

law reader_disposal_failure_is_retained:
  for -Transport: Data
  for cause: Reader.Error<Transport>
  {Body.outcome(Transport, Fail{cause}, Done{Unit{}}) == Fail{Body.ReaderFailure{cause}} : Result<&2, &2, Body.CloseError<Transport>, Unit>}

law body_disposal_failure_is_retained:
  for -Transport: Data
  for cause: SSE.ReadError<Transport>
  {Body.outcome(Transport, Done{Unit{}}, Fail{cause}) == Fail{Body.BodyFailure{cause}} : Result<&2, &2, Body.CloseError<Transport>, Unit>}

law simultaneous_disposal_failures_are_retained_in_order:
  for -Transport: Data
  for reader: Reader.Error<Transport>
  for body: SSE.ReadError<Transport>
  {Body.outcome(Transport, Fail{reader}, Fail{body}) == Fail{Body.BothFailures{reader, body}} : Result<&2, &2, Body.CloseError<Transport>, Unit>}
