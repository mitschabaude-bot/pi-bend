import Base
import ../packages/ai/src/api/openai-responses-cleartext-fetch.bend as Native
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/http-connect.bend as Connect
import ../packages/runtime/src/connection-driver.bend as Driver
import ../packages/runtime/src/http-resolved-exchange.bend as HTTP
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/http-exchange-plan.bend as Plan

law successful_headers_transfer_response:
  for -Reason: Data
  for -SourceError: Data
  for resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError)
  for attempts: List<&2, Driver.Entry<Deadline.Cause<Reason>>>
  for response: Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>
  {Native.headed(Reason, SourceError, resolution, attempts, Done{response}) == Done{response} : Result<&2, &1, Native.Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>}

law header_failure_retains_trace_and_cause:
  for -Reason: Data
  for -SourceError: Data
  for resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError)
  for attempts: List<&2, Driver.Entry<Deadline.Cause<Reason>>>
  for cause: Progress.Error<Exchange.ReadError<Deadline.Cause<Reason>>>
  {Native.headed(Reason, SourceError, resolution, attempts, Fail{cause}) == Fail{Native.HeaderFailure{resolution, attempts, cause}} : Result<&2, &1, Native.Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>}

law rejected_plan_has_no_header_effects:
  for -Reason: Data
  for -SourceError: Data
  for cause: Plan.Error
  {Native.resolved(Reason, SourceError, HTTP.Rejected{cause}) == IO.pure(Result<&2, &1, Native.Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>, Fail{Native.Rejected{cause}}) : IO(Result<&2, &1, Native.Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>)}

law unresolved_request_preserves_resolution:
  for -Reason: Data
  for -SourceError: Data
  for resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError)
  {Native.resolved(Reason, SourceError, HTTP.Unresolved{resolution}) == IO.pure(Result<&2, &1, Native.Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>, Fail{Native.Unresolved{resolution}}) : IO(Result<&2, &1, Native.Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>)}

law exchange_failure_precedes_header_read:
  for -Reason: Data
  for -SourceError: Data
  for resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError)
  for attempts: List<&2, Driver.Entry<Deadline.Cause<Reason>>>
  for cause: HTTP.Error<Deadline.Cause<Reason>>
  {Native.resolved(Reason, SourceError, HTTP.Attempted{resolution, attempts, Fail{cause}}) == IO.pure(Result<&2, &1, Native.Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>, Fail{Native.ExchangeFailure{resolution, attempts, cause}}) : IO(Result<&2, &1, Native.Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>)}
