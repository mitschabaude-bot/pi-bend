import Base
import ./provider-fetch.bend as Http
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-message.bend as Headers
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/timer.bend as Timer
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/schema-value.bend as V

# One HTTP exchange of a credential provider: the AWS SDK's credential
# services (STS, SSO, container and instance metadata) and google-auth-library's
# token endpoints and metadata server. The whole response body is read as
# text; a timeout (milliseconds) bounds the exchange.

type Transport<-Reason: Data> is Data:
  Transport{fetch: Fetch.Fetch(Reason), urlContext: URL.Context, signal: Abort.AbortSignal<Reason>}

type Reply is Data:
  Reply{status: U32, headers: Headers.Headers, body: String}

type Failure is Data:
  TimedOut{}
  Unreachable{}
  Aborted{}
  InvalidRequest{message: String}

def NO_TIMEOUT() -> U32: 4294967295

def contextOf(-Reason: Data, transport: Transport<Reason>) -> URL.Context:
  match transport:
    case Transport{_, context, _}: context

def signalOf(-Reason: Data, transport: Transport<Reason>) -> Abort.AbortSignal<Reason>:
  match transport:
    case Transport{_, _, signal}: signal

def successful(reply: Reply) -> Bool:
  match reply:
    case Reply{+status, _, _}: U32.is_ge(status, 200) && U32.is_lt(status, 300)

def headerValue(value: Result<&2, &2, Headers.HeaderSyntaxError, Maybe<&2, String>>) -> Maybe<&2, String>:
  match value:
    case Done{found}: found
    case Fail{_}: None{}

# A response header, if present and well-formed.
def header(reply: Reply, name: String) -> Maybe<&2, String>:
  match reply:
    case Reply{_, headers, _}: headerValue(Headers.get(headers, name))

def bodyText(-Reason: Data, text: Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String>) -> String:
  match text:
    case Done{body}: body
    case Fail{_}: ""

def failedWith(expired: Bool, aborted: Bool) -> Failure:
  Bool.pick(Failure, aborted, Aborted{}, Bool.pick(Failure, expired, TimedOut{}, Unreachable{}))

def isExpired(-Reason: Data, closed: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> Bool:
  match closed:
    case Some{Abort.Supplied{Deadline.Expired{}}}: True{}
    case _: False{}

def text(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{SCon{c, cs}}}: Some{SCon{c, cs}}
    case _: None{}

def received(~Reason: Data, response: Fetch.Result_(Reason)) -> IO(Maybe<&2, Reply>):
  match response:
    case Fail{_}: IO.pure(Maybe<&2, Reply>, None{})
    case Done{Response.Response{+metadata, body}}:
      do IO<Maybe<&2, Reply>>:
        text : Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String> <- Http.responseText(~Reason, 16777216n, body)
        return Some{Reply{Response.metadataStatus(metadata), Response.headers(metadata), bodyText(Reason, text)}}

def classified(-Reason: Data, result: Maybe<&2, Reply>, closed: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>, aborted: Bool) -> Result<&2, &2, Failure, Reply>:
  match result:
    case Some{reply}: Done{reply}
    case None{}: Fail{failedWith(isExpired(Reason, closed), aborted)}

def exchanged(~Reason: Data, fetch: Fetch.Fetch(Reason), +parent: Abort.AbortSignal<Reason>, url: URL.URL, method: String, headers: Headers.Headers, body: Headers.Input, pair: Deadline.Scope<Reason> & Fetch.Signal(Reason)) -> IO(Result<&2, &2, Failure, Reply>):
  match pair:
    case (scope, signal):
      do IO<Result<&2, &2, Failure, Reply>>:
        response : Fetch.Result_(Reason) <- C.call(Fetch.Input<Reason>, Fetch.Result_(Reason), fetch, Fetch.Input{url, method, headers, body, signal})
        result : Maybe<&2, Reply> <- received(~Reason, response)
        closed : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        aborted : Bool <- Abort.aborted(Reason, parent)
        return classified(Reason, result, closed, aborted)

# Host and Content-Length are written by the transport from the URL and body.
def headerFields(fields: List<&2, R.Property<String>>) -> List<&2, R.Property<String>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{+name, value} <> rest:
      +tail = headerFields(rest)
      Bool.pick(List<&2, R.Property<String>>, String.eq(String.to_lower(name), "host") || String.eq(String.to_lower(name), "content-length"), tail, R.Property{name, value} <> tail)

def sendHeaders(~Reason: Data, transport: Transport<Reason>, +method: String, url: Result<&2, &2, URL.Error, URL.URL>, built: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, body: Headers.Input, timeout: U32) -> IO(Result<&2, &2, Failure, Reply>):
  match transport url built:
    case _ Fail{_} _: IO.pure(Result<&2, &2, Failure, Reply>, Fail{InvalidRequest{"Invalid URL"}})
    case _ _ Fail{_}: IO.pure(Result<&2, &2, Failure, Reply>, Fail{InvalidRequest{"Invalid header value"}})
    case Transport{fetch, _, +signal} Done{address} Done{headers}:
      do IO<Result<&2, &2, Failure, Reply>>:
        scope : Deadline.Scope<Reason> <- Deadline.create(Reason, timeout, signal)
        exchanged(~Reason, fetch, signal, address, method, headers, body, Deadline.borrow(Reason, scope))

# One request under a timeout (milliseconds; NO_TIMEOUT for none).
def request(~Reason: Data, +transport: Transport<Reason>, method: String, url: String, fields: List<&2, R.Property<String>>, body: Headers.Input, timeout: U32) -> IO(Result<&2, &2, Failure, Reply>):
  sendHeaders(~Reason, transport, method, URL.parse(contextOf(Reason, transport), url), Http.headerList(headerFields(fields)), body, timeout)

# gaxios errors
# -------------

def jsonOf(result: Result<&2, &2, Decode.ParseError, V.Value>) -> Maybe<&2, V.Value>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}

def failureText(failure: Failure) -> String:
  match failure:
    case TimedOut{}: "The operation was aborted due to timeout"
    case Unreachable{}: "fetch failed"
    case Aborted{}: "This operation was aborted"
    case InvalidRequest{message}: message

def apiErrorObject(+status: U32, fields: R.Record<V.Value>) -> String:
  Maybe.default(&2, String, text(R.get(V.Value, fields, "message")), "Request failed with status code " ++ U32.show(status))

def apiErrorField(+status: U32, +body: String, error: Maybe<&2, V.Value>) -> String:
  match error:
    case Some{V.Text{SCon{c, cs}}}: SCon{c, cs}
    case Some{V.ObjectValue{fields}}: apiErrorObject(status, fields)
    case _: "Request failed with status code " ++ U32.show(status)

def apiErrorWith(+status: U32, +body: String, json: Maybe<&2, V.Value>) -> String:
  match json:
    case Some{V.ObjectValue{fields}}: apiErrorField(status, body, R.get(V.Value, fields, "error"))
    case _: Bool.pick(String, String.is_empty(body), "Request failed with status code " ++ U32.show(status), body)

# GaxiosError's message for a failed status: an `error` string, an
# `error.message`, a text body, else the status.
def apiError(+status: U32, +body: String) -> String: apiErrorWith(status, body, jsonOf(Decode.parse(body)))

# gaxios retries
# --------------

# A request's retryConfig: how many retries in all (`retry`), how many of
# them may follow a failure without any response, and the methods retried.
type Retry is Data:
  Retry{retry: Nat, noResponseRetries: Nat, methods: List<&2, String>}
  NoRetry{}

# gaxios' defaults for a request that enables retries.
def DEFAULT_RETRY() -> Retry: Retry{3n, 2n, ["GET", "HEAD", "PUT", "OPTIONS", "DELETE"]}

# google-auth-library's RETRY_CONFIG: the defaults, with POST retried too.
def AUTH_RETRY() -> Retry: Retry{3n, 2n, ["GET", "PUT", "POST", "HEAD", "OPTIONS", "DELETE"]}

def listed(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case first <> rest: String.eq(first, name) || listed(rest, name)

def retriedStatus(+status: U32) -> Bool:
  (U32.is_ge(status, 100) && U32.is_le(status, 199)) || U32.is_eq(status, 408) || U32.is_eq(status, 429) || (U32.is_ge(status, 500) && U32.is_le(status, 599))

def retryWith(config: Retry, +method: String, +attempt: Nat, status: Maybe<&2, U32>) -> Bool:
  match config status:
    case NoRetry{} _: False{}
    case Retry{retry, noResponse, methods} None{}: Nat.is_lt(attempt, noResponse) && listed(methods, String.to_upper(method)) && Nat.is_lt(attempt, retry)
    case Retry{retry, _, methods} Some{code}: listed(methods, String.to_upper(method)) && retriedStatus(code) && Nat.is_lt(attempt, retry)

# shouldRetryRequest after `attempt` retries.
def shouldRetry(config: Retry, +method: String, +attempt: Nat, result: Result<&2, &2, Failure, Reply>) -> Bool:
  match config result:
    case NoRetry{} _: False{}
    case _ Done{Reply{+status, _, _}}: Bool.pick(Bool, U32.is_ge(status, 200) && U32.is_lt(status, 300), False{}, retryWith(config, method, attempt, Some{status}))
    case _ Fail{Aborted{}}: False{}
    case _ Fail{InvalidRequest{_}}: False{}
    case _ Fail{_}: retryWith(config, method, attempt, None{})

# getNextRetryDelay: 100 ms, then (2^n - 1) / 2 seconds.
def retryDelay(+attempt: Nat) -> U32:
  match attempt:
    case 0n: 100
    case 1n: 500
    case 2n: 1500
    case _: 3500

@unsafe def retrying(~Reason: Data, +transport: Transport<Reason>, +config: Retry, +method: String, +url: String, +fields: List<&2, R.Property<String>>, +body: Headers.Input, +timeout: U32, +attempt: Nat) -> IO(Result<&2, &2, Failure, Reply>):
  do IO<Result<&2, &2, Failure, Reply>>:
    +result : Result<&2, &2, Failure, Reply> <- request(~Reason, transport, method, url, fields, body, timeout)
    Bool.pick(Unit -> IO(Result<&2, &2, Failure, Reply>), shouldRetry(config, method, attempt, result), _ =>
      do IO<Result<&2, &2, Failure, Reply>>:
        slept : Result<&2, &2, Abort.AbortReason<Reason>, Unit> <- Timer.sleep(Reason, retryDelay(attempt), signalOf(Reason, transport))
        retrying(~Reason, transport, config, method, url, fields, body, timeout, 1n + attempt), _ => IO.pure(Result<&2, &2, Failure, Reply>, result))(Unit{})

# A request under gaxios' retry policy.
def requestRetrying(~Reason: Data, +transport: Transport<Reason>, config: Retry, method: String, url: String, fields: List<&2, R.Property<String>>, body: Headers.Input, timeout: U32) -> IO(Result<&2, &2, Failure, Reply>):
  retrying(~Reason, transport, config, method, url, fields, body, timeout, 0n)
