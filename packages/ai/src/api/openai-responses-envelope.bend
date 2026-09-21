import Base
import ../types.bend as T
import ../utils/json.bend as JSON
import ../utils/json-finite.bend as Finite
import ./openai-request-headers.bend as Header
import ./openai-responses-url.bend as Address
import ../../../runtime/src/url-record.bend as URL
import ../../../runtime/src/url-absolute.bend as Absolute
import ../../../runtime/src/headers.bend as Headers
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F

# An immutable, unframed request works with either custom fetch or native HTTP.
# Signal/callback handles remain borrowed at the transport/session boundary.
type Request is Data:
  Request{url: URL.URL, method: String, headers: Headers.Headers, body: String, timeout: F.F64}

type Error is Data:
  URLFailure{cause: Address.Error}
  HeaderFailure{cause: Header.Error}
  NonFinitePayload{}
  PayloadEncodingFailure{}

def bodyHeaders() -> T.ProviderHeaders():
  R.Record{R.Property{"content-type", T.PresentValue{"application/json"}} <> Nil{}}

def encoding(result: Maybe<&2, String>) -> Result<&2, &2, Error, String>:
  match result:
    case None{}: Fail{PayloadEncodingFailure{}}
    case Some{text}: Done{text}

def encoded(payload: T.JsonValue, valid: Bool) -> Result<&2, &2, Error, String>:
  match valid:
    case False{}: Fail{NonFinitePayload{}}
    case True{}: encoding(JSON.stringify(payload))

def serialize(+payload: T.JsonValue) -> Result<&2, &2, Error, String>:
  encoded(payload, Finite.valid(payload))

def completed(url: URL.URL, body: String, timeout: F.F64, headers: Result<&2, &2, Header.Error, Headers.Headers>) -> Result<&2, &2, Error, Request>:
  match headers:
    case Fail{cause}: Fail{HeaderFailure{cause}}
    case Done{fields}: Done{Request{url, "post", fields, body, timeout}}

def timeoutHeader(original: Maybe<&2, F.F64>) -> Result<&2, &2, Header.Error, Maybe<&2, String>>:
  match original:
    case None{}: Done{None{}}
    case Some{+value}: Header.timeoutField(value, F.compare(value, F.fromU32(0)))

def serialized(configuration: Header.Defaults, apiKey: String, client: T.ProviderHeaders(), url: URL.URL, timeout: F.F64, original: Maybe<&2, F.F64>, body: Result<&2, &2, Error, String>) -> Result<&2, &2, Error, Request>:
  match body:
    case Fail{cause}: Fail{cause}
    case Done{text}: completed(url, text, timeout, Header.layered(configuration, apiKey, Zero{}, Some{client}, Some{bodyHeaders()}, None{}, timeoutHeader(original)))

def timed(configuration: Header.Defaults, apiKey: String, client: T.ProviderHeaders(), url: URL.URL, payload: T.JsonValue, original: Maybe<&2, F.F64>, timeout: Result<&2, &2, Header.Error, F.F64>) -> Result<&2, &2, Error, Request>:
  match timeout:
    case Fail{cause}: Fail{HeaderFailure{cause}}
    case Done{value}: serialized(configuration, apiKey, client, url, value, original, serialize(payload))

# SDK preparation order is URL, timeout, body, headers. The hook's chosen
# payload is passed explicitly; this layer neither invokes nor retries hooks.
def addressed(configuration: Header.Defaults, apiKey: String, client: T.ProviderHeaders(), +timeout: Maybe<&2, F.F64>, payload: T.JsonValue, url: Result<&2, &2, Address.Error, URL.URL>) -> Result<&2, &2, Error, Request>:
  match url:
    case Fail{cause}: Fail{URLFailure{cause}}
    case Done{value}: timed(configuration, apiKey, client, value, payload, timeout, Header.validateTimeout(Header.effectiveTimeout(timeout)))

def prepare(context: Absolute.Context, configuration: Header.Defaults, apiKey: String, client: T.ProviderHeaders(), baseUrl: String, timeout: Maybe<&2, F.F64>, payload: T.JsonValue) -> Result<&2, &2, Error, Request>:
  addressed(configuration, apiKey, client, timeout, payload, Address.prepare(context, baseUrl))
