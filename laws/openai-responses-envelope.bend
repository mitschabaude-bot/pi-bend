import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses-envelope.bend as E
import ../packages/ai/src/api/openai-request-headers.bend as H
import ../packages/ai/src/api/openai-responses-url.bend as A
import ../packages/runtime/src/url-record.bend as URL
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/f64.bend as F

law invalid_payload_has_no_body:
  for payload: T.JsonValue
  {E.encoded(payload, False{}) == Fail{E.NonFinitePayload{}} : Result<&2, &2, E.Error, String>}

law encoding_retains_text:
  for text: String
  {E.encoding(Some{text}) == Done{text} : Result<&2, &2, E.Error, String>}

law completed_request_retains_fields:
  for url: URL.URL
  for body: String
  for timeout: F.F64
  for headers: Headers.Headers
  {E.completed(url, body, timeout, Done{headers}) == Done{E.Request{url, "post", headers, body, timeout}} : Result<&2, &2, E.Error, E.Request>}

law completed_error_retains_cause:
  for url: URL.URL
  for body: String
  for timeout: F.F64
  for cause: H.Error
  {E.completed(url, body, timeout, Fail{cause}) == Fail{E.HeaderFailure{cause}} : Result<&2, &2, E.Error, E.Request>}

law url_failure_precedes_other_validation:
  for configuration: H.Defaults
  for key: String
  for headers: T.ProviderHeaders()
  for timeout: Maybe<&2, F.F64>
  for payload: T.JsonValue
  for cause: A.Error
  {E.addressed(configuration, key, headers, timeout, payload, Fail{cause}) == Fail{E.URLFailure{cause}} : Result<&2, &2, E.Error, E.Request>}

law timeout_failure_precedes_payload:
  for configuration: H.Defaults
  for key: String
  for headers: T.ProviderHeaders()
  for url: URL.URL
  for payload: T.JsonValue
  for original: Maybe<&2, F.F64>
  for cause: H.Error
  {E.timed(configuration, key, headers, url, payload, original, Fail{cause}) == Fail{E.HeaderFailure{cause}} : Result<&2, &2, E.Error, E.Request>}

law payload_failure_precedes_headers:
  for configuration: H.Defaults
  for key: String
  for headers: T.ProviderHeaders()
  for url: URL.URL
  for timeout: F.F64
  for original: Maybe<&2, F.F64>
  for cause: E.Error
  {E.serialized(configuration, key, headers, url, timeout, original, Fail{cause}) == Fail{cause} : Result<&2, &2, E.Error, E.Request>}

law absent_timeout_has_no_header:
  {E.timeoutHeader(None{}) == Done{None{}} : Result<&2, &2, H.Error, Maybe<&2, String>>}
