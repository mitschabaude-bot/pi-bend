import Base
import ../types.bend as Auth
import ../../api/credential-http.bend as Http
import ../../utils/json.bend as Wire
import ../../utils/schema-json.bend as Convert
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/fetch.bend as Fetch
import ../../../../runtime/src/http-message.bend as Headers
import ../../../../runtime/src/json.bend as Decode
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/url.bend as URL

# The HTTP pieces the device-code and key-exchange OAuth flows share:
# fetch-shaped requests (form or JSON bodies) whose whole body is read,
# `response.json()`-style parsing, and the field and URL checks the flows
# apply to provider responses.

type Flow is Data:
  Flow{fetch: Fetch.Fetch(Unit), url: URL.Context}

def flowContext(flow: Flow) -> URL.Context:
  match flow:
    case Flow{_, url}: url

# A received response: status, whole body text and its JSON object (upstream
# `response.json()` narrowed to an object; None when the body is not JSON or
# not an object).
type Reply is Data:
  Reply{status: U32, headers: Headers.Headers, text: String, json: Maybe<&2, V.Value>}

def replyStatus(reply: Reply) -> U32:
  match reply:
    case Reply{status, _, _, _}: status

def replyText(reply: Reply) -> String:
  match reply:
    case Reply{_, _, text, _}: text

def replyJson(reply: Reply) -> Maybe<&2, V.Value>:
  match reply:
    case Reply{_, _, _, json}: json

def replyHeader(reply: Reply, name: String) -> Maybe<&2, String>:
  match reply:
    case Reply{_, headers, _, _}: Http.headerValue(Headers.get(headers, name))

def ok(reply: Reply) -> Bool:
  match reply:
    case Reply{+status, _, _, _}: U32.is_ge(status, 200) && U32.is_lt(status, 300)

def parsedJson(result: Result<&2, &2, Decode.ParseError, V.Value>) -> Maybe<&2, V.Value>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}

def replyOf(reply: Http.Reply) -> Reply:
  match reply:
    case Http.Reply{status, headers, +body}: Reply{status, headers, body, parsedJson(Decode.parse(body))}

def replied(result: Result<&2, &2, Http.Failure, Http.Reply>) -> Result<&2, &2, Http.Failure, Reply>:
  match result:
    case Done{reply}: Done{replyOf(reply)}
    case Fail{failure}: Fail{failure}

# One request; `timeout` in milliseconds (Http.NO_TIMEOUT for none).
def send(flow: Flow, +signal: Abort.AbortSignal<Unit>, method: String, url: String, headers: List<&2, R.Property<String>>, body: Headers.Input, timeout: U32) -> IO(Result<&2, &2, Http.Failure, Reply>):
  match flow:
    case Flow{fetch, context}:
      do IO<Result<&2, &2, Http.Failure, Reply>>:
        result : Result<&2, &2, Http.Failure, Http.Reply> <- Http.request(~Unit, Http.Transport{fetch, context, signal}, method, url, headers, body, timeout)
        return replied(result)

# `new URLSearchParams(fields)` as a request body.
def formParams(fields: List<&2, R.Property<String>>, params: URL.URLSearchParams) -> URL.URLSearchParams:
  match fields:
    case Nil{}: params
    case R.Property{name, value} <> rest: formParams(rest, URL.append(params, name, value))

def form(fields: List<&2, R.Property<String>>) -> Headers.Input: Headers.SearchParams{formParams(fields, URL.new())}

# `new URLSearchParams(fields).toString()`.
def formText(fields: List<&2, R.Property<String>>) -> String: URL.toString(formParams(fields, URL.new()))

# JSON fields
# -----------
def objectFields(json: Maybe<&2, V.Value>) -> R.Record<V.Value>:
  match json:
    case Some{V.ObjectValue{fields}}: fields
    case _: R.new(V.Value)

def field(json: Maybe<&2, V.Value>, name: String) -> Maybe<&2, V.Value>: R.get(V.Value, objectFields(json), name)

def isObject(json: Maybe<&2, V.Value>) -> Bool:
  match json:
    case Some{V.ObjectValue{_}}: True{}
    case _: False{}

# typeof value === "string"
def textOf(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{text}}: Some{text}
    case _: None{}

def nonEmptyOf(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{SCon{c, cs}}}: Some{SCon{c, cs}}
    case _: None{}

def stringField(json: Maybe<&2, V.Value>, name: String) -> Maybe<&2, String>: textOf(field(json, name))

# typeof value === "string" && value (non-empty)
def nonEmptyField(json: Maybe<&2, V.Value>, name: String) -> Maybe<&2, String>: nonEmptyOf(field(json, name))

def numberOf(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{number}}: Some{number}
    case _: None{}

# typeof value === "number"
def numberField(json: Maybe<&2, V.Value>, name: String) -> Maybe<&2, F64>: numberOf(field(json, name))

def finitePositive(+value: F64) -> Bool:
  Bool.not(F.isNaN(value)) && F.isGreater(F.compare(value, F.fromU32(0))) && F.isGreater(F.compare(F.infinity(False{}), value))

def positiveOf(value: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match value:
    case Some{+number}: Bool.pick(Maybe<&2, F64>, finitePositive(number), Some{number}, None{})
    case None{}: None{}

# typeof value === "number" && Number.isFinite(value) && value > 0
def positiveField(json: Maybe<&2, V.Value>, name: String) -> Maybe<&2, F64>: positiveOf(numberField(json, name))

# JSON.stringify of the parsed body (null when there was none).
def jsonText(json: Maybe<&2, V.Value>) -> String:
  match json:
    case Some{value}: Maybe.default(&2, String, Wire.stringify(Convert.toJson(value)), "null")
    case None{}: "null"

# URLs
# ----
def schemeAllowed(scheme: URL.Scheme, httpsOnly: Bool) -> Bool:
  match scheme:
    case URL.Https{}: True{}
    case URL.Http{}: Bool.not(httpsOnly)
    case _: False{}

def trustedParsed(parsed: Result<&2, &2, URL.Error, URL.URL>, httpsOnly: Bool) -> Maybe<&2, String>:
  match parsed:
    case Done{URL.URL{+scheme, username, password, host, port, path, query, fragment}}: Bool.pick(Maybe<&2, String>, schemeAllowed(scheme, httpsOnly), Some{URL.href(URL.URL{scheme, username, password, host, port, path, query, fragment})}, None{})
    case Fail{_}: None{}

# `new URL(value)` with an http(s) (or https-only) protocol, as its href; the
# verification URI is opened in the user's browser.
def trustedUrl(context: URL.Context, value: Maybe<&2, String>, httpsOnly: Bool) -> Maybe<&2, String>:
  match value:
    case Some{SCon{c, cs}}: trustedParsed(URL.parse(context, SCon{c, cs}), httpsOnly)
    case _: None{}

# Present or the message.
def orFail(-A: Data, value: Maybe<&2, A>, message: String) -> Result<&2, &2, String, A>:
  match value:
    case Some{found}: Done{found}
    case None{}: Fail{message}

# Messages
# --------
def statusText(status: U32) -> String: U32.show(status)

def failureText(failure: Http.Failure) -> String: Http.failureText(failure)
