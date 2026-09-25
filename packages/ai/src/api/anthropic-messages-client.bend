import Base
import ../types.bend as T
import ../utils/json.bend as JsonWire
import ../utils/json-parse.bend as JsonRepair
import ./anthropic-messages.bend as Messages
import ./anthropic-messages-stream.bend as Stream
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-exchange.bend as Exchange
import ../../../runtime/src/http-message.bend as Headers
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/json.bend as JsonParse
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/sse.bend as SSE
import ../../../runtime/src/url.bend as URL

# A live Anthropic request uses the runtime fetch and SSE reader directly.
# The event callback is borrowed for this call and receives each immutable
# assistant event as soon as it is decoded.
def Transport(-Reason: Data) -> Type: Fetch.Transport(Reason)
def ReadError(-Reason: Data) -> Data: Response.ResponseProgressError<Exchange.ReadError<Deadline.Cause<Reason>>>
def Events(-G: Data) -> Data: C.Callback<T.AssistantMessageEvent<V.Value, G>, Unit>

type Error<-Reason: Data> is Data:
  InvalidURL{cause: URL.Error}
  InvalidHeader{cause: Headers.HeaderSyntaxError}
  InvalidPayload{}
  MissingAuth{}
  FetchFailure{cause: Fetch.Error<Reason>}
  HTTPFailure{status: U32}
  ReadFailure{cause: ReadError(Reason)}
  MalformedEvent{data: String}
  ProviderFailure{message: String}

type Request is Data:
  Request{url: URL.URL, headers: Headers.Headers, body: String}

def addressReversed(base: String, reversed: String) -> String:
  match reversed:
    case SCon{'/', _}: base ++ "v1/messages"
    case _: base ++ "/v1/messages"

def address(+base: String) -> String: addressReversed(base, String.reverse(base))

def authHeader(key: String) -> String:
  Bool.pick(String, String.contains(key, "sk-ant-oat"), "Authorization", "x-api-key")

def authValue(+key: String) -> String:
  Bool.pick(String, String.contains(key, "sk-ant-oat"), "Bearer " ++ key, key)

def layer(fields: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, name: String, value: String) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match fields:
    case Fail{cause}: Fail{cause}
    case Done{current}: Headers.set(current, name, value)

def deleted(fields: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, name: String) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match fields:
    case Fail{cause}: Fail{cause}
    case Done{current}: Headers.delete(current, name)

def customHeaders(values: List<&2, R.Property<T.Nullable<String>>>, fields: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match values:
    case Nil{}: fields
    case R.Property{name, T.NullValue{}} <> rest: customHeaders(rest, deleted(fields, name))
    case R.Property{name, T.PresentValue{value}} <> rest: customHeaders(rest, layer(fields, name, value))

def configuredHeaders(base: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, custom: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match custom:
    case None{}: base
    case Some{fields}: customHeaders(R.entries(T.Nullable<String>, fields), base)

def hasAuth(values: List<&2, R.Property<T.Nullable<String>>>) -> Bool:
  match values:
    case Nil{}: False{}
    case R.Property{name, T.PresentValue{value}} <> rest:
      +key = String.to_lower(name)
      (String.eq(key, "authorization") || String.eq(key, "x-api-key") || String.eq(key, "cf-aig-authorization")) && Bool.not(String.is_empty(value)) || hasAuth(rest)
    case _ <> rest: hasAuth(rest)

def authPresent(custom: Maybe<&2, T.ProviderHeaders()>) -> Bool:
  match custom:
    case None{}: False{}
    case Some{fields}: hasAuth(R.entries(T.Nullable<String>, fields))

def requestHeadersWith(base: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, key: Maybe<&2, String>, custom: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match key:
    case None{}: configuredHeaders(base, custom)
    case Some{+value}: configuredHeaders(layer(base, authHeader(value), authValue(value)), custom)

def betaStrings(values: List<&2, T.JsonValue>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case T.JsonString{value} <> rest: value <> betaStrings(rest)
    case _ <> rest: betaStrings(rest)

def betaValue(value: Maybe<&2, T.JsonValue>) -> Maybe<&2, String>:
  match value:
    case Some{T.JsonArray{values}}: Some{String.join(betaStrings(values), ",")}
    case _: None{}

def betaHeader(payload: T.JsonValue) -> Maybe<&2, String>:
  match payload:
    case T.JsonObject{fields}: betaValue(R.get(T.JsonValue, fields, "betas"))
    case _: None{}

def wirePayload(payload: T.JsonValue) -> T.JsonValue:
  match payload:
    case T.JsonObject{fields}: T.JsonObject{R.remove(T.JsonValue, fields, "betas")}
    case other: other

def withBeta(fields: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, beta: Maybe<&2, String>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match beta:
    case None{}: fields
    case Some{value}: layer(fields, "anthropic-beta", value)

def oauthIdentity(fields: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, oauth: Bool) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match oauth:
    case False{}: fields
    case True{}:
      layer(layer(layer(fields, "anthropic-dangerous-direct-browser-access", "true"), "user-agent", "claude-cli/2.1.280"), "x-app", "cli")
def oauthHeaders(fields: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, key: Maybe<&2, String>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match key:
    case None{}: fields
    case Some{value}: oauthIdentity(fields, String.contains(value, "sk-ant-oat"))

def requestHeaders(+key: Maybe<&2, String>, custom: Maybe<&2, T.ProviderHeaders()>, beta: Maybe<&2, String>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  requestHeadersWith(oauthHeaders(withBeta(layer(layer(layer(Done{Headers.new()}, "accept", "application/json"), "content-type", "application/json"), "anthropic-version", "2023-06-01"), beta), key), key, custom)

def encoded(-Reason: Data, url: URL.URL, fields: Headers.Headers, body: Maybe<&2, String>) -> Result<&2, &2, Error<Reason>, Request>:
  match body:
    case None{}: Fail{InvalidPayload{}}
    case Some{text}: Done{Request{url, fields, text}}

def withHeaders(-Reason: Data, url: URL.URL, body: Maybe<&2, String>, headers: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>) -> Result<&2, &2, Error<Reason>, Request>:
  match headers:
    case Fail{cause}: Fail{InvalidHeader{cause}}
    case Done{fields}: encoded(Reason, url, fields, body)

def withURL(-Reason: Data, body: Maybe<&2, String>, fields: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, url: Result<&2, &2, URL.Error, URL.URL>) -> Result<&2, &2, Error<Reason>, Request>:
  match url:
    case Fail{cause}: Fail{InvalidURL{cause}}
    case Done{value}: withHeaders(Reason, value, body, fields)

def isSome(-A: Data, value: Maybe<&2, A>) -> Bool:
  match value:
    case None{}: False{}
    case Some{_}: True{}

def prepare(-Reason: Data, -G: Data, -D: Data, urlContext: URL.Context, +model: T.Model<T.JsonValue>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Messages.Options, +key: Maybe<&2, String>, +custom: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, Error<Reason>, Request>:
  match model:
    case T.Model{_, _, _, _, +base, _, _, _, _, _, _, _, _, _, _, _}:
      +payload = Messages.buildParams(G, D, model, context, options)
      Bool.pick(Result<&2, &2, Error<Reason>, Request>, authPresent(custom) || isSome(String, key), withURL(Reason, JsonWire.stringify(wirePayload(payload)), requestHeaders(key, custom, betaHeader(payload)), URL.parse(urlContext, address(base))), Fail{MissingAuth{}})

def publish(-G: Data, +callback: Events(G), events: List<&2, T.AssistantMessageEvent<V.Value, G>>) -> IO(Unit):
  match events:
    case Nil{}: IO.pure(Unit, Unit{})
    case event <> rest:
      do IO<Unit>:
        C.call(T.AssistantMessageEvent<V.Value, G>, Unit, callback, event)
        publish(G, callback, rest)

def emitted(-G: Data, step: Stream.Step<G>) -> List<&2, T.AssistantMessageEvent<V.Value, G>>:
  match step:
    case Stream.Step{_, events, _}: events

def output(-G: Data, current: Stream.State<G>) -> T.AssistantMessage<V.Value, G>:
  match current:
    case Stream.State{message, _, _, _}: message

def settled(-Reason: Data, -G: Data, step: Stream.Step<G>) -> Result<&2, &2, Error<Reason>, Stream.State<G>>:
  match step:
    case Stream.Step{current, _, None{}}: Done{current}
    case Stream.Step{_, _, Some{cause}}: Fail{ProviderFailure{cause}}

def after(-Reason: Data, -G: Data, callback: Events(G), +step: Stream.Step<G>) -> IO(Result<&2, &2, Error<Reason>, Stream.State<G>>):
  do IO<Result<&2, &2, Error<Reason>, Stream.State<G>>>:
    publish(G, callback, emitted(G, step))
    return settled(Reason, G, step)

def publishFailure(-Reason: Data, -G: Data, callback: Events(G), current: Stream.State<G>, message: String, cause: Error<Reason>) -> IO(Result<&2, &2, Error<Reason>, Stream.State<G>>):
  do IO<Result<&2, &2, Error<Reason>, Stream.State<G>>>:
    publish(G, callback, emitted(G, Stream.failed(G, current, message)))
    return Fail{cause}

def parsed(-Reason: Data, -G: Data, callback: Events(G), model: T.Model<T.JsonValue>, current: Stream.State<G>, data: String, result: Result<&2, &2, JsonParse.ParseError, V.Value>) -> IO(Result<&2, &2, Error<Reason>, Stream.State<G>>):
  match result:
    case Fail{_}: publishFailure(Reason, G, callback, current, "Malformed Anthropic SSE event", MalformedEvent{data})
    case Done{value}: after(Reason, G, callback, Stream.event(G, current, value, model))

def known(+kind: String) -> Bool:
  String.eq(kind, "message_start") || String.eq(kind, "message_delta") || String.eq(kind, "message_stop") || String.eq(kind, "content_block_start") || String.eq(kind, "content_block_delta") || String.eq(kind, "content_block_stop")

def dispatchAllowed(-Reason: Data, -G: Data, callback: Events(G), model: T.Model<T.JsonValue>, current: Stream.State<G>, +data: String, allowed: Bool) -> IO(Result<&2, &2, Error<Reason>, Stream.State<G>>):
  match allowed:
    case True{}: parsed(Reason, G, callback, model, current, data, JsonRepair.parseJsonWithRepair(data))
    case False{}: IO.pure(Result<&2, &2, Error<Reason>, Stream.State<G>>, Done{current})

def dispatchNamed(-Reason: Data, -G: Data, callback: Events(G), model: T.Model<T.JsonValue>, current: Stream.State<G>, kind: String, data: String) -> IO(Result<&2, &2, Error<Reason>, Stream.State<G>>):
  dispatchAllowed(Reason, G, callback, model, current, data, known(kind))

def dispatch(-Reason: Data, -G: Data, callback: Events(G), model: T.Model<T.JsonValue>, current: Stream.State<G>, event: SSE.ServerSentEvent) -> IO(Result<&2, &2, Error<Reason>, Stream.State<G>>):
  match event:
    case SSE.ServerSentEvent{Some{"error"}, +data, _}: publishFailure(Reason, G, callback, current, data, ProviderFailure{data})
    case SSE.ServerSentEvent{Some{kind}, data, _}: dispatchNamed(Reason, G, callback, model, current, kind, data)
    case _: IO.pure(Result<&2, &2, Error<Reason>, Stream.State<G>>, Done{current})

type Decision<-Reason: Data, -G: Data> is Type:
  ReadMore{cursor: SSE.Cursor<ReadError(Reason)>, current: Stream.State<G>}
  Process{cursor: SSE.Cursor<ReadError(Reason)>, current: Stream.State<G>, event: SSE.ServerSentEvent}
  Finish{cursor: SSE.Cursor<ReadError(Reason)>, current: Stream.State<G>}
  ReadFailed{cursor: SSE.Cursor<ReadError(Reason)>, current: Stream.State<G>, cause: ReadError(Reason)}
  Return{cursor: SSE.Cursor<ReadError(Reason)>, result: Result<&2, &2, Error<Reason>, Stream.State<G>>}

def fromNext(-Reason: Data, -G: Data, current: Stream.State<G>, next: SSE.Next<ReadError(Reason)>) -> Decision<Reason, G>:
  match next:
    case SSE.Next{cursor, Fail{cause}}: ReadFailed{cursor, current, cause}
    case SSE.Next{cursor, Done{None{}}}: Finish{cursor, current}
    case SSE.Next{cursor, Done{Some{event}}}: Process{cursor, current, event}

def fromResult(-Reason: Data, -G: Data, cursor: SSE.Cursor<ReadError(Reason)>, result: Result<&2, &2, Error<Reason>, Stream.State<G>>) -> Decision<Reason, G>:
  match result:
    case Fail{cause}: Return{cursor, Fail{cause}}
    case Done{current}: ReadMore{cursor, current}

@unsafe def drive(~Reason: Data, ~G: Data, +callback: Events(G), +model: T.Model<T.JsonValue>, decision: Decision<Reason, G>) -> IO(SSE.Cursor<ReadError(Reason)> & Result<&2, &2, Error<Reason>, Stream.State<G>>):
  match decision:
    case ReadMore{cursor, current}:
      do IO<SSE.Cursor<ReadError(Reason)> & Result<&2, &2, Error<Reason>, Stream.State<G>>>:
        next : SSE.Next<ReadError(Reason)> <- SSE.nextReader(ReadError(Reason), cursor)
        drive(~Reason, ~G, callback, model, fromNext(Reason, G, current, next))
    case Process{cursor, current, event}:
      do IO<SSE.Cursor<ReadError(Reason)> & Result<&2, &2, Error<Reason>, Stream.State<G>>>:
        result : Result<&2, &2, Error<Reason>, Stream.State<G>> <- dispatch(Reason, G, callback, model, current, event)
        drive(~Reason, ~G, callback, model, fromResult(Reason, G, cursor, result))
    case Finish{cursor, current}:
      do IO<SSE.Cursor<ReadError(Reason)> & Result<&2, &2, Error<Reason>, Stream.State<G>>>:
        result : Result<&2, &2, Error<Reason>, Stream.State<G>> <- after(Reason, G, callback, Stream.finish(G, current))
        return (cursor, result)
    case ReadFailed{cursor, current, cause}:
      do IO<SSE.Cursor<ReadError(Reason)> & Result<&2, &2, Error<Reason>, Stream.State<G>>>:
        result : Result<&2, &2, Error<Reason>, Stream.State<G>> <- publishFailure(Reason, G, callback, current, "Could not read Anthropic SSE response", ReadFailure{cause})
        return (cursor, result)
    case Return{cursor, result}: IO.pure(SSE.Cursor<ReadError(Reason)> & Result<&2, &2, Error<Reason>, Stream.State<G>>, (cursor, result))

def resultMessage(-Reason: Data, -G: Data, result: Result<&2, &2, Error<Reason>, Stream.State<G>>) -> Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{current}: Done{output(G, current)}

def release(-Reason: Data, -G: Data, owner: Response.Owner<Transport(Reason), ReadError(Reason)>, pair: SSE.Cursor<ReadError(Reason)> & Result<&2, &2, Error<Reason>, Stream.State<G>>) -> IO(Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>):
  match pair:
    case (cursor, result):
      do IO<Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>>:
        closed : SSE.CloseResult<ReadError(Reason)> <- SSE.closeReader(ReadError(Reason), cursor)
        disposed : Result<&2, &2, ReadError(Reason), Unit> <- Response.dispose(Transport(Reason), ReadError(Reason), owner)
        return resultMessage(Reason, G, result)

def identity(-Reason: Data, value: ReadError(Reason)) -> ReadError(Reason): value

def readOwned(~Reason: Data, ~G: Data, callback: Events(G), model: T.Model<T.JsonValue>, current: Stream.State<G>, pair: Response.Owner<Transport(Reason), ReadError(Reason)> & SSE.Source<ReadError(Reason)>) -> IO(Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>):
  match pair:
    case (owner, source):
      do IO<Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>>:
        result : SSE.Cursor<ReadError(Reason)> & Result<&2, &2, Error<Reason>, Stream.State<G>> <- drive(~Reason, ~G, callback, model, ReadMore{SSE.createReader(ReadError(Reason), source), current})
        release(Reason, G, owner, result)

def bodySource(~Reason: Data, ~G: Data, callback: Events(G), model: T.Model<T.JsonValue>, current: Stream.State<G>, body: Response.Body<Transport(Reason)>) -> IO(Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>):
  do IO<Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>>:
    owner : Response.Owner<Transport(Reason), ReadError(Reason)> <- Exchange.responseSource(~(Deadline.Cause<Reason>), ~ReadError(Reason), ~identity(Reason), body)
    readOwned(~Reason, ~G, callback, model, current, Response.borrow(Transport(Reason), ReadError(Reason), owner))

def receivedStatus(~Reason: Data, ~G: Data, +callback: Events(G), model: T.Model<T.JsonValue>, +current: Stream.State<G>, body: Response.Body<Transport(Reason)>, code: U32, success: Bool) -> IO(Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>):
  match success:
    case True{}:
      do IO<Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>>:
        publish(G, callback, T.Start{output(G, current)} <> Nil{})
        bodySource(~Reason, ~G, callback, model, current, body)
    case False{}:
      do IO<Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>>:
        owner : Response.Owner<Transport(Reason), ReadError(Reason)> <- Exchange.responseSource(~(Deadline.Cause<Reason>), ~ReadError(Reason), ~identity(Reason), body)
        released : Result<&2, &2, ReadError(Reason), Unit> <- Response.dispose(Transport(Reason), ReadError(Reason), owner)
        publish(G, callback, emitted(G, Stream.failed(G, current, "Anthropic HTTP request failed")))
        return Fail{HTTPFailure{code}}

def received(~Reason: Data, ~G: Data, callback: Events(G), model: T.Model<T.JsonValue>, current: Stream.State<G>, response: Response.Response<Transport(Reason)>) -> IO(Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>):
  match response:
    case Response.Response{+metadata, body}: receivedStatus(~Reason, ~G, callback, model, current, body, Response.metadataStatus(metadata), Response.successful(Response.metadataStatus(metadata)))

def receivedFetch(~Reason: Data, ~G: Data, callback: Events(G), +model: T.Model<T.JsonValue>, timestamp: F64, response: Fetch.Result_(Reason)) -> IO(Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>):
  match response:
    case Fail{cause}:
      do IO<Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>>:
        publish(G, callback, emitted(G, Stream.failed(G, Stream.create(G, model, timestamp), "Anthropic request failed")))
        return Fail{FetchFailure{cause}}
    case Done{value}: received(~Reason, ~G, callback, model, Stream.create(G, model, timestamp), value)

def run(~Reason: Data, ~G: Data, fetch: Fetch.Fetch(Reason), signal: Fetch.Signal(Reason), callback: Events(G), model: T.Model<T.JsonValue>, request: Request, timestamp: F64) -> IO(Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>):
  match request:
    case Request{url, headers, body}:
      do IO<Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>>:
        response : Fetch.Result_(Reason) <- C.call(Fetch.Input<Reason>, Fetch.Result_(Reason), fetch, Fetch.Input{url, "POST", headers, Headers.Text{body}, signal})
        receivedFetch(~Reason, ~G, callback, model, timestamp, response)
