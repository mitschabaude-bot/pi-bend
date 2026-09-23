import Base
import ../types.bend as T
import ../utils/json.bend as JsonWire
import ../utils/json-parse.bend as JsonRepair
import ../utils/headers.bend as HeaderUtils
import ../utils/provider-retry.bend as Retry
import ./google-generative-ai.bend as Google
import ./constrained-sampling.bend as Constrained
import ./google-generative-ai-stream.bend as Stream
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-exchange.bend as Exchange
import ../../../runtime/src/http-message.bend as Headers
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/json.bend as JsonParse
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/random.bend as Seed
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/sse.bend as SSE
import ../../../runtime/src/timer.bend as Timer
import ../../../runtime/src/url.bend as URL

def Transport(-Reason: Data) -> Type: Fetch.Transport(Reason)
def ReadError(-Reason: Data) -> Data: Response.ResponseProgressError<Exchange.ReadError<Deadline.Cause<Reason>>>
def Events(-G: Data) -> Data: C.Callback<T.AssistantMessageEvent<V.Value, G>, Unit>

type Error<-Reason: Data> is Data:
  InvalidURL{cause: URL.Error}
  InvalidHeader{cause: Headers.HeaderSyntaxError}
  InvalidPayload{}
  UnsupportedPayloadModel{}
  InvalidToolConfig{message: String}
  MissingAuth{}
  FetchFailure{cause: Fetch.Error<Reason>}
  HTTPFailure{status: U32}
  ReadFailure{cause: ReadError(Reason)}
  MalformedEvent{data: String}
  ProviderFailure{message: String}
  RetryAborted{}
  RetryDelayRejected{cause: Retry.DelayError}
  RetrySleepRejected{cause: Timer.Error}
  RetryEntropyFailure{cause: Seed.SeedError}
  RetryOptionsFailure{cause: Retry.OptionsError}

type AttemptError<-Reason: Data> is Data:
  AttemptTransport{cause: Fetch.Error<Reason>}
  AttemptHTTP{status: U32}

type Request is Data:
  Request{url: URL.URL, headers: Headers.Headers, body: String}

type Prepared is Data:
  Prepared{request: Request, payload: T.JsonValue}

def replacedRequest(-Reason: Data, request: Request, body: String) -> Result<&2, &2, Error<Reason>, Request>:
  match request:
    case Request{url, headers, _}: Done{Request{url, headers, body}}

def replaced(-Reason: Data, request: Request, value: Maybe<&2, String>) -> Result<&2, &2, Error<Reason>, Request>:
  match value:
    case None{}: Fail{InvalidPayload{}}
    case Some{body}: replacedRequest(Reason, request, body)

def wireBody(value: Maybe<&2, T.JsonValue>) -> Maybe<&2, String>:
  match value:
    case None{}: None{}
    case Some{payload}: JsonWire.stringify(payload)

def modelField(value: Maybe<&2, T.JsonValue>) -> Maybe<&2, String>:
  match value:
    case Some{T.JsonString{id}}: Some{id}
    case _: None{}

def payloadModel(params: T.JsonValue) -> Maybe<&2, String>:
  match params:
    case T.JsonObject{fields}: modelField(R.get(T.JsonValue, fields, "model"))
    case _: None{}

def validPayloadModel(-Reason: Data, request: Request, payload: T.JsonValue, original: String, selected: Maybe<&2, String>) -> Result<&2, &2, Error<Reason>, Request>:
  match selected:
    case Some{id}: Bool.pick(Result<&2, &2, Error<Reason>, Request>, String.eq(id, original), replaced(Reason, request, wireBody(Google.wireParams(payload))), Fail{UnsupportedPayloadModel{}})
    case None{}: Fail{InvalidPayload{}}

def replacePayload(-Reason: Data, request: Request, +payload: T.JsonValue, original: String) -> Result<&2, &2, Error<Reason>, Request>:
  validPayloadModel(Reason, request, payload, original, payloadModel(payload))

def addressEnd(base: String, reversed: String, id: String) -> String:
  match reversed:
    case SCon{'/', _}: base ++ "models/" ++ id ++ ":streamGenerateContent?alt=sse"
    case _: base ++ "/models/" ++ id ++ ":streamGenerateContent?alt=sse"

def address(+base: String, id: String) -> String:
  addressEnd(base, String.reverse(base), URL.encode(URL.Component{}, id))

def layer(fields: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, name: String, value: String) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match fields:
    case Fail{cause}: Fail{cause}
    case Done{current}: Headers.set(current, name, value)

def baseHeaders(key: String) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  layer(layer(layer(Done{Headers.new()}, "accept", "text/event-stream"), "content-type", "application/json"), "x-goog-api-key", key)

def fromConfiguration(current: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, config: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match current:
    case Fail{cause}: Fail{cause}
    case Done{headers}: HeaderUtils.apply(headers, config)

def withHeaders(base: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, configured: Maybe<&2, R.Record<String>>, custom: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  fromConfiguration(fromConfiguration(base, Some{HeaderUtils.overlayStrings(R.new(T.Nullable<String>), configured)}), custom)

def encoded(-Reason: Data, url: URL.URL, fields: Headers.Headers, body: Maybe<&2, String>) -> Result<&2, &2, Error<Reason>, Request>:
  match body:
    case None{}: Fail{InvalidPayload{}}
    case Some{text}: Done{Request{url, fields, text}}

def validHeaders(-Reason: Data, url: URL.URL, body: Maybe<&2, String>, headers: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>) -> Result<&2, &2, Error<Reason>, Request>:
  match headers:
    case Fail{cause}: Fail{InvalidHeader{cause}}
    case Done{fields}: encoded(Reason, url, fields, body)

def validURL(-Reason: Data, body: Maybe<&2, String>, headers: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, url: Result<&2, &2, URL.Error, URL.URL>) -> Result<&2, &2, Error<Reason>, Request>:
  match url:
    case Fail{cause}: Fail{InvalidURL{cause}}
    case Done{parsedUrl}: validHeaders(Reason, parsedUrl, body, headers)

def included(-Reason: Data, id: String, payload: T.JsonValue, result: Result<&2, &2, Error<Reason>, Request>) -> Result<&2, &2, Error<Reason>, Prepared>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{request}: Done{Prepared{request, Google.sdkParams(id, payload)}}

def encodedPayload(-Reason: Data, urlContext: URL.Context, base: String, +id: String, key: String, headers: Maybe<&2, R.Record<String>>, custom: Maybe<&2, T.ProviderHeaders()>, result: Result<&2, &2, Constrained.Error, T.JsonValue>) -> Result<&2, &2, Error<Reason>, Prepared>:
  match result:
    case Fail{cause}: Fail{InvalidToolConfig{Constrained.errorMessage(cause)}}
    case Done{+payload}: included(Reason, id, payload, validURL(Reason, JsonWire.stringify(payload), withHeaders(baseHeaders(key), headers, custom), URL.parse(urlContext, address(base, id))))

def keyValue(-Reason: Data, -G: Data, -D: Data, urlContext: URL.Context, +model: T.Model<T.JsonValue>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Google.Options, key: String, custom: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, Error<Reason>, Prepared>:
  match model:
    case T.Model{id, _, _, _, base, _, _, _, _, _, _, _, _, _, headers, _}:
      encodedPayload(Reason, urlContext, base, id, key, headers, custom, Google.buildParams(G, D, model, context, options))

def prepareDetailed(-Reason: Data, -G: Data, -D: Data, urlContext: URL.Context, model: T.Model<T.JsonValue>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Google.Options, key: Maybe<&2, String>, custom: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, Error<Reason>, Prepared>:
  match key:
    case None{}: Fail{MissingAuth{}}
    case Some{SNil{}}: Fail{MissingAuth{}}
    case Some{value}: keyValue(Reason, G, D, urlContext, model, context, options, value, custom)

def requestOf(-Reason: Data, value: Result<&2, &2, Error<Reason>, Prepared>) -> Result<&2, &2, Error<Reason>, Request>:
  match value:
    case Fail{cause}: Fail{cause}
    case Done{Prepared{request, _}}: Done{request}

def prepare(-Reason: Data, -G: Data, -D: Data, urlContext: URL.Context, model: T.Model<T.JsonValue>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Google.Options, key: Maybe<&2, String>, custom: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, Error<Reason>, Request>:
  requestOf(Reason, prepareDetailed(Reason, G, D, urlContext, model, context, options, key, custom))

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
    case Stream.State{message, _, _, _, _}: message

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
    case Fail{_}: publishFailure(Reason, G, callback, current, "Malformed Google SSE event", MalformedEvent{data})
    case Done{value}: after(Reason, G, callback, Stream.chunk(G, current, value, model))

def dispatchData(-Reason: Data, -G: Data, callback: Events(G), model: T.Model<T.JsonValue>, current: Stream.State<G>, +data: String, done: Bool) -> IO(Result<&2, &2, Error<Reason>, Stream.State<G>>):
  match done:
    case True{}: IO.pure(Result<&2, &2, Error<Reason>, Stream.State<G>>, Done{current})
    case False{}: parsed(Reason, G, callback, model, current, data, JsonRepair.parseJsonWithRepair(data))

def dispatch(-Reason: Data, -G: Data, callback: Events(G), model: T.Model<T.JsonValue>, current: Stream.State<G>, event: SSE.ServerSentEvent) -> IO(Result<&2, &2, Error<Reason>, Stream.State<G>>):
  match event:
    case SSE.ServerSentEvent{Some{"error"}, +data, _}: publishFailure(Reason, G, callback, current, data, ProviderFailure{data})
    case SSE.ServerSentEvent{_, +data, _}: dispatchData(Reason, G, callback, model, current, data, String.eq(data, "[DONE]"))

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
        result : Result<&2, &2, Error<Reason>, Stream.State<G>> <- publishFailure(Reason, G, callback, current, "Could not read Google SSE response", ReadFailure{cause})
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
        publish(G, callback, emitted(G, Stream.failed(G, current, "Google HTTP request failed")))
        return Fail{HTTPFailure{code}}

def received(~Reason: Data, ~G: Data, callback: Events(G), model: T.Model<T.JsonValue>, current: Stream.State<G>, response: Response.Response<Transport(Reason)>) -> IO(Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>):
  match response:
    case Response.Response{+metadata, body}: receivedStatus(~Reason, ~G, callback, model, current, body, Response.metadataStatus(metadata), Response.successful(Response.metadataStatus(metadata)))

def receivedFetch(~Reason: Data, ~G: Data, callback: Events(G), +model: T.Model<T.JsonValue>, timestamp: F64, response: Fetch.Result_(Reason)) -> IO(Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>):
  match response:
    case Fail{cause}:
      do IO<Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>>:
        publish(G, callback, emitted(G, Stream.failed(G, Stream.create(G, model, timestamp), "Google request failed")))
        return Fail{FetchFailure{cause}}
    case Done{value}: received(~Reason, ~G, callback, model, Stream.create(G, model, timestamp), value)

type AttemptEnvironment<-Reason: Data> is Data:
  AttemptEnvironment{request: Request, fetch: Fetch.Fetch(Reason), signal: Fetch.Signal(Reason)}

def attemptedStatus(~Reason: Data, metadata: Response.Metadata, body: Response.Body<Transport(Reason)>, +status: U32, success: Bool) -> IO(Result<&2, &1, Retry.RequestFailure<AttemptError<Reason>>, Response.Response<Transport(Reason)>>):
  match success:
    case True{}: IO.pure(Result<&2, &1, Retry.RequestFailure<AttemptError<Reason>>, Response.Response<Transport(Reason)>>, Done{Response.Response{metadata, body}})
    case False{}:
      do IO<Result<&2, &1, Retry.RequestFailure<AttemptError<Reason>>, Response.Response<Transport(Reason)>>>:
        owner : Response.Owner<Transport(Reason), ReadError(Reason)> <- Exchange.responseSource(~(Deadline.Cause<Reason>), ~ReadError(Reason), ~identity(Reason), body)
        released : Result<&2, &2, ReadError(Reason), Unit> <- Response.dispose(Transport(Reason), ReadError(Reason), owner)
        return Fail{Retry.Provider{Retry.ProviderError{AttemptHTTP{status}, "Google HTTP request failed", Some{F.fromU32(status)}, None{}, None{}, None{}}}}

def attemptedResponse(~Reason: Data, response: Response.Response<Transport(Reason)>) -> IO(Result<&2, &1, Retry.RequestFailure<AttemptError<Reason>>, Response.Response<Transport(Reason)>>):
  match response:
    case Response.Response{+metadata, body}:
      +status = Response.metadataStatus(metadata)
      attemptedStatus(~Reason, metadata, body, status, Response.successful(status))

def attemptedFetch(~Reason: Data, value: Fetch.Result_(Reason)) -> IO(Result<&2, &1, Retry.RequestFailure<AttemptError<Reason>>, Response.Response<Transport(Reason)>>):
  match value:
    case Fail{cause}: IO.pure(Result<&2, &1, Retry.RequestFailure<AttemptError<Reason>>, Response.Response<Transport(Reason)>>, Fail{Retry.Other{AttemptTransport{cause}}})
    case Done{response}: attemptedResponse(~Reason, response)

def attemptBody(~Reason: Data, environment: AttemptEnvironment<Reason>, unused: Unit) -> IO(Result<&2, &1, Retry.RequestFailure<AttemptError<Reason>>, Response.Response<Transport(Reason)>>):
  match environment:
    case AttemptEnvironment{Request{url, headers, body}, fetch, signal}:
      do IO<Result<&2, &1, Retry.RequestFailure<AttemptError<Reason>>, Response.Response<Transport(Reason)>>>:
        response : Fetch.Result_(Reason) <- C.call(Fetch.Input<Reason>, Fetch.Result_(Reason), fetch, Fetch.Input{url, "POST", headers, Headers.Text{body}, signal})
        attemptedFetch(~Reason, response)

def attemptError(-Reason: Data, value: AttemptError<Reason>) -> Error<Reason>:
  match value:
    case AttemptTransport{cause}: FetchFailure{cause}
    case AttemptHTTP{status}: HTTPFailure{status}

def retryError(-Reason: Data, value: Retry.RetryFailure<AttemptError<Reason>>) -> Error<Reason>:
  match value:
    case Retry.RequestFailed{failure}: attemptError(Reason, Retry.original(AttemptError<Reason>, failure))
    case Retry.RequestAborted{}: RetryAborted{}
    case Retry.DelayRejected{cause, _}: RetryDelayRejected{cause}
    case Retry.SleepRejected{cause}: RetrySleepRejected{cause}

def retried(-Reason: Data, value: Result<&2, &1, Retry.RetryFailure<AttemptError<Reason>>, Response.Response<Transport(Reason)>>) -> Result<&2, &1, Error<Reason>, Response.Response<Transport(Reason)>>:
  match value:
    case Fail{cause}: Fail{retryError(Reason, cause)}
    case Done{response}: Done{response}

def attemptWithEffects(~Reason: Data, environment: AttemptEnvironment<Reason>, options: Retry.ProviderRetryOptions<Deadline.Cause<Reason>>, date: C.Callback<String, F64>, pair: Retry.Runtime<Deadline.Cause<Reason>> & Retry.Effects<Deadline.Cause<Reason>>) -> IO(Result<&2, &1, Error<Reason>, Response.Response<Transport(Reason)>>):
  match pair:
    case (owner, effects):
      do IO<Result<&2, &1, Error<Reason>, Response.Response<Transport(Reason)>>>:
        +request : C.Callback<Unit, Result<&2, &1, Retry.RequestFailure<AttemptError<Reason>>, Response.Response<Transport(Reason)>>> <- C.create(~AttemptEnvironment<Reason>, ~Unit, ~Result<&2, &1, Retry.RequestFailure<AttemptError<Reason>>, Response.Response<Transport(Reason)>>, ~(attemptBody(~Reason)), environment)
        result : Result<&2, &1, Retry.RetryFailure<AttemptError<Reason>>, Response.Response<Transport(Reason)>> <- Retry.retryProviderRequestOwned(Deadline.Cause<Reason>, AttemptError<Reason>, Response.Response<Transport(Reason)>, request, effects, options)
        C.dispose(Unit, Result<&2, &1, Retry.RequestFailure<AttemptError<Reason>>, Response.Response<Transport(Reason)>>, request)
        Retry.dispose(Deadline.Cause<Reason>, owner)
        C.dispose(String, F64, date)
        return retried(Reason, result)

def seeded(~Reason: Data, environment: AttemptEnvironment<Reason>, options: Retry.ProviderRetryOptions<Deadline.Cause<Reason>>, date: C.Callback<String, F64>, result: Result<&2, &1, Seed.SeedError, Retry.Runtime<Deadline.Cause<Reason>>>) -> IO(Result<&2, &1, Error<Reason>, Response.Response<Transport(Reason)>>):
  match result:
    case Fail{cause}:
      do IO<Result<&2, &1, Error<Reason>, Response.Response<Transport(Reason)>>>:
        C.dispose(String, F64, date)
        return Fail{RetryEntropyFailure{cause}}
    case Done{runtime}: attemptWithEffects(~Reason, environment, options, date, Retry.borrow(Deadline.Cause<Reason>, runtime))

def acquire(~Reason: Data, fetch: Fetch.Fetch(Reason), signal: Fetch.Signal(Reason), request: Request, options: Retry.ProviderRetryOptions<Deadline.Cause<Reason>>) -> IO(Result<&2, &1, Error<Reason>, Response.Response<Transport(Reason)>>):
  do IO<Result<&2, &1, Error<Reason>, Response.Response<Transport(Reason)>>>:
    +date : C.Callback<String, F64> <- Retry.dateParser()
    runtime : Result<&2, &1, Seed.SeedError, Retry.Runtime<Deadline.Cause<Reason>>> <- Retry.new(~(Deadline.Cause<Reason>), date)
    seeded(~Reason, AttemptEnvironment{request, fetch, signal}, options, date, runtime)

def receivedRetry(~Reason: Data, ~G: Data, callback: Events(G), +model: T.Model<T.JsonValue>, timestamp: F64, result: Result<&2, &1, Error<Reason>, Response.Response<Transport(Reason)>>) -> IO(Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>):
  match result:
    case Fail{cause}:
      do IO<Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>>:
        publish(G, callback, emitted(G, Stream.failed(G, Stream.create(G, model, timestamp), "Google request failed")))
        return Fail{cause}
    case Done{response}: received(~Reason, ~G, callback, model, Stream.create(G, model, timestamp), response)

def resolvedRetry(~Reason: Data, ~G: Data, fetch: Fetch.Fetch(Reason), signal: Fetch.Signal(Reason), callback: Events(G), model: T.Model<T.JsonValue>, request: Request, timestamp: F64, result: Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Deadline.Cause<Reason>>>) -> IO(Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>):
  match result:
    case Fail{cause}:
      do IO<Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>>:
        publish(G, callback, emitted(G, Stream.failed(G, Stream.create(G, model, timestamp), "Invalid Google retry options")))
        return Fail{RetryOptionsFailure{cause}}
    case Done{options}:
      do IO<Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>>:
        response : Result<&2, &1, Error<Reason>, Response.Response<Transport(Reason)>> <- acquire(~Reason, fetch, signal, request, options)
        receivedRetry(~Reason, ~G, callback, model, timestamp, response)

def run(~Reason: Data, ~G: Data, fetch: Fetch.Fetch(Reason), signal: Fetch.Signal(Reason), callback: Events(G), model: T.Model<T.JsonValue>, request: Request, timestamp: F64) -> IO(Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>):
  match request:
    case Request{url, headers, body}:
      do IO<Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>>:
        response : Fetch.Result_(Reason) <- C.call(Fetch.Input<Reason>, Fetch.Result_(Reason), fetch, Fetch.Input{url, "POST", headers, Headers.Text{body}, signal})
        receivedFetch(~Reason, ~G, callback, model, timestamp, response)

def runWithRetry(~Reason: Data, ~G: Data, fetch: Fetch.Fetch(Reason), +signal: Fetch.Signal(Reason), callback: Events(G), model: T.Model<T.JsonValue>, request: Request, timestamp: F64, maxRetries: Maybe<&2, F64>, maxRetryDelayMs: Maybe<&2, F64>) -> IO(Result<&2, &2, Error<Reason>, T.AssistantMessage<V.Value, G>>):
  match maxRetries:
    case None{}: run(~Reason, ~G, fetch, signal, callback, model, request, timestamp)
    case Some{count}: resolvedRetry(~Reason, ~G, fetch, signal, callback, model, request, timestamp, Retry.resolve(Deadline.Cause<Reason>, Some{count}, maxRetryDelayMs, Some{signal}))
