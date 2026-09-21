import Base
import ../packages/ai/src/api/openai-responses-fetch.bend as Fetch
import ../packages/ai/src/api/openai-responses-envelope.bend as Envelope
import ../packages/runtime/src/url-record.bend as URL
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/callback.bend as C

law fetch_input_retains_request:
  for -Reason: Data
  for url: URL.URL
  for method: String
  for headers: Headers.Headers
  for body: String
  for timeout: F.F64
  for signal: Abort.AbortSignal<Deadline.Cause<Reason>>
  {Fetch.input(Reason, Envelope.Request{url, method, headers, body, timeout}, signal) == Fetch.Input{url, String.to_upper(method), headers, body, signal} : Fetch.Input<Reason>}

law absent_custom_fetch_selects_native:
  for -Reason: Data
  for -E: Data
  for -Transport: Type
  for native: C.Callback<Fetch.Input<Reason>, Result<&2, &1, E, Response.Response<Transport>>>
  {Fetch.choose(Reason, E, Transport, native, None{}) == native : C.Callback<Fetch.Input<Reason>, Result<&2, &1, E, Response.Response<Transport>>>}

law custom_fetch_takes_precedence:
  for -Reason: Data
  for -E: Data
  for -Transport: Type
  for native: C.Callback<Fetch.Input<Reason>, Result<&2, &1, E, Response.Response<Transport>>>
  for custom: C.Callback<Fetch.Input<Reason>, Result<&2, &1, E, Response.Response<Transport>>>
  {Fetch.choose(Reason, E, Transport, native, Some{custom}) == custom : C.Callback<Fetch.Input<Reason>, Result<&2, &1, E, Response.Response<Transport>>>}
