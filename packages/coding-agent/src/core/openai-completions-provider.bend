import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/api/openai-completions.bend as Request
import ../../../ai/src/api/openai-completions-client.bend as Client
import ../../../ai/src/api/constrained-sampling.bend as Sampling
import ../../../ai/src/api/openai-completions-stream.bend as Fold
import ../../../ai/src/api/simple-options.bend as Simple
import ../../../ai/src/utils/transcript.bend as Transcript
import ../../../ai/src/utils/event-stream.bend as Events
import ../../../agent/src/types.bend as Agent
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/pi-user-agent.bend as UserAgent
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/url.bend as URL
import ./tools/index.bend as Tools

def Details() -> Data: Tools.ToolDetails
def Error() -> Data: Tools.ToolError
def Options() -> Data: Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>
def Context() -> Data: Ai.TranscriptContext<V.Value, V.Value, Unit, Details()>
def Stream() -> Data: Events.AssistantMessageEventStream(V.Value, Unit)
def Output() -> Type: Result<&2, &1, Error(), Agent.StreamLease<Unit, Error()>>

def pushEvent(stream: Stream(), event: Ai.AssistantMessageEvent<V.Value, Unit>) -> IO(Unit):
  Events.push(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, stream, event)
def pushFailureStep(stream: Stream(), step: Fold.Step<Unit>) -> IO(Unit):
  match step:
    case Fold.Step{_, event <> _, _}: pushEvent(stream, event)
    case _: IO.pure(Unit, Unit{})
def pushFailure(stream: Stream(), model: Ai.Model<Ai.JsonValue>, timestamp: F64, message: String) -> IO(Unit):
  pushFailureStep(stream, Fold.failed(Unit, Fold.create(Unit, model, timestamp), message))

def modelId(model: Ai.Model<Ai.JsonValue>) -> String:
  match model:
    case Ai.Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: id

# upstream OpenAICompletionsOptions, which streamSimple derives from the
# simple options.
def Completions() -> Data: Request.Options(Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error())
def Base() -> Data: Ai.StreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>

def base(options: Completions()) -> Base(): Request.baseOf(Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error(), options)

def keyOf(value: Base()) -> Maybe<&2, String>:
  match value:
    case Ai.StreamOptions{_, _, key, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: key

def envOf(value: Base()) -> Maybe<&2, Ai.ProviderEnv()>:
  match value:
    case Ai.StreamOptions{_, _, _, _, env, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: env

def payloadHookOf(value: Base()) -> Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, Error())>:
  match value:
    case Ai.StreamOptions{_, _, _, _, _, hook, _, _, _, _, _, _, _, _, _, _, _, _, _}: hook

def headersOf(value: Base()) -> Maybe<&2, Ai.ProviderHeaders()>:
  match value:
    case Ai.StreamOptions{_, _, _, _, _, _, _, headers, _, _, _, _, _, _, _, _, _, _, _}: headers

def timeoutOf(value: Base()) -> Maybe<&2, F64>:
  match value:
    case Ai.StreamOptions{_, _, _, _, _, _, _, _, timeout, _, _, _, _, _, _, _, _, _, _}: timeout

def retriesOf(value: Base()) -> Maybe<&2, F64>:
  match value:
    case Ai.StreamOptions{_, _, _, _, _, _, _, _, _, retries, _, _, _, _, _, _, _, _, _}: retries

def delayOf(value: Base()) -> Maybe<&2, F64>:
  match value:
    case Ai.StreamOptions{_, _, _, _, _, _, _, _, _, _, delay, _, _, _, _, _, _, _, _}: delay

def retentionOf(value: Base()) -> Maybe<&2, Ai.CacheRetention>:
  match value:
    case Ai.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, retention, _, _, _}: retention

def sessionOf(value: Base()) -> Maybe<&2, String>:
  match value:
    case Ai.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, session, _, _}: session

def signalOf(value: Base()) -> Maybe<&2, Abort.AbortSignal<Unit>>:
  match value:
    case Ai.StreamOptions{signal, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: signal

def timeoutNumber(value: Result<&2, &2, F.Error, Nat>) -> U32:
  match value:
    case Done{number}: U32.from_nat(Nat.min(4294967295n, number))
    case Fail{_}: 600000

def timeoutValue(value: Maybe<&2, F64>) -> U32:
  match value:
    case None{}: 600000
    case Some{milliseconds}: timeoutNumber(F.convert(F.truncate(milliseconds)))

def timeout(value: Base()) -> U32: timeoutValue(timeoutOf(value))

def resolvedOptions(value: Maybe<&2, Options()>) -> Options():
  match value:
    case None{}: Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error())
    case Some{selected}: selected

def preparedRequest(stream: Stream(), callback: Client.Events(Unit), fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), model: Ai.Model<Ai.JsonValue>, timestamp: F64, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, value: Result<&2, &2, Client.Error<Unit>, Client.Request>) -> IO(Unit):
  match value:
    case Fail{Client.UnsupportedPayloadModel{}}: pushFailure(stream, model, timestamp, "Completions onPayload cannot change the model in the native adapter")
    case Fail{Client.UnsupportedCompat{message}}: pushFailure(stream, model, timestamp, "Unsupported Completions compatibility: " ++ message)
    case Fail{_}: pushFailure(stream, model, timestamp, "Could not prepare Completions request")
    case Done{request}:
      do IO<Unit>:
        result : Result<&2, &2, Client.Error<Unit>, Ai.AssistantMessage<V.Value, Unit>> <- Client.runWithRetry(~Unit, ~Unit, fetch, signal, callback, model, request, timestamp, retries, delay)
        return Unit{}

def hookedPayload(stream: Stream(), callback: Client.Events(Unit), fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), +model: Ai.Model<Ai.JsonValue>, timestamp: F64, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, request: Client.Request, result: Result<&2, &2, Error(), Maybe<&2, Ai.JsonValue>>) -> IO(Unit):
  match result:
    case Fail{cause}: pushFailure(stream, model, timestamp, Tools.errorMessage(cause))
    case Done{None{}}: preparedRequest(stream, callback, fetch, signal, model, timestamp, retries, delay, Done{request})
    case Done{Some{payload}}: preparedRequest(stream, callback, fetch, signal, model, timestamp, retries, delay, Client.replacePayload(Unit, request, payload, modelId(model)))

def preparedPayload(stream: Stream(), callback: Client.Events(Unit), fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), +model: Ai.Model<Ai.JsonValue>, timestamp: F64, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, request: Client.Request, payload: Ai.JsonValue, hook: Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, Error())>) -> IO(Unit):
  match hook:
    case None{}: preparedRequest(stream, callback, fetch, signal, model, timestamp, retries, delay, Done{request})
    case Some{selected}:
      do IO<Unit>:
        result : Result<&2, &2, Error(), Maybe<&2, Ai.JsonValue>> <- C.call(Ai.PayloadInput<Ai.JsonValue, Ai.Model<Ai.JsonValue>>, Result<&2, &2, Error(), Maybe<&2, Ai.JsonValue>>, selected, Ai.PayloadInput{payload, model})
        hookedPayload(stream, callback, fetch, signal, model, timestamp, retries, delay, request, result)

def preparedWithHook(stream: Stream(), callback: Client.Events(Unit), fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), +model: Ai.Model<Ai.JsonValue>, timestamp: F64, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, value: Client.Prepared, hook: Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, Error())>) -> IO(Unit):
  match value:
    case Client.Prepared{request, payload}: preparedPayload(stream, callback, fetch, signal, model, timestamp, retries, delay, request, payload, hook)

def prepared(stream: Stream(), callback: Client.Events(Unit), fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), model: Ai.Model<Ai.JsonValue>, timestamp: F64, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, hook: Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, Error())>, value: Result<&2, &2, Client.Error<Unit>, Client.Prepared>) -> IO(Unit):
  match value:
    case Fail{_}: pushFailure(stream, model, timestamp, "Could not prepare Completions request")
    case Done{detailed}: preparedWithHook(stream, callback, fetch, signal, model, timestamp, retries, delay, detailed, hook)

def payloaded(stream: Stream(), callback: Client.Events(Unit), fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), urlContext: URL.Context, +model: Ai.Model<Ai.JsonValue>, +options: Base(), timestamp: F64, agent: String, headers: Maybe<&2, Ai.ProviderHeaders()>, params: Request.ParamsResult()) -> IO(Unit):
  match params:
    case Fail{error}: pushFailure(stream, model, timestamp, Sampling.errorMessage(error))
    case Done{payload}: prepared(stream, callback, fetch, signal, model, timestamp, retriesOf(options), delayOf(options), payloadHookOf(options), Client.prepare(Unit, urlContext, model, payload, keyOf(options), agent, headers))

def built(stream: Stream(), callback: Client.Events(Unit), fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), urlContext: URL.Context, +model: Ai.Model<Ai.JsonValue>, +context: Context(), +options: Completions(), timestamp: F64, agent: String, +compat: Request.Compat(), +retention: Ai.CacheRetention, properties: R.Record<String>) -> IO(Unit):
  +shared = base(options)
  do IO<Unit>:
    params : Request.ParamsResult() <- Request.buildParams(~Unit, ~Details(), ~Abort.AbortSignal<Unit>, ~Unit, ~Fetch.Fetch(Unit), ~Error(), model, context, options, compat, retention, properties)
    payloaded(stream, callback, fetch, signal, urlContext, model, shared, timestamp, agent, Request.clientHeaders(compat, Request.cacheSessionId(retention, sessionOf(shared)), headersOf(shared)), params)

def supportedGrammar(stream: Stream(), callback: Client.Events(Unit), fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), urlContext: URL.Context, +model: Ai.Model<Ai.JsonValue>, context: Context(), options: Completions(), timestamp: F64, agent: String, compat: Request.Compat(), retention: Ai.CacheRetention, +properties: R.Record<String>, issue: Maybe<&2, String>) -> IO(Unit):
  match issue:
    case Some{message}: pushFailure(stream, model, timestamp, "Unsupported Completions compatibility: " ++ message)
    case None{}: built(stream, callback, fetch, signal, urlContext, model, context, options, timestamp, agent, compat, retention, properties)

def grammarResolved(stream: Stream(), callback: Client.Events(Unit), fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), urlContext: URL.Context, +model: Ai.Model<Ai.JsonValue>, context: Context(), options: Completions(), timestamp: F64, agent: String, compat: Request.Compat(), retention: Ai.CacheRetention, properties: Result<&2, &2, Sampling.Error, R.Record<String>>) -> IO(Unit):
  match properties:
    case Fail{error}: pushFailure(stream, model, timestamp, Sampling.errorMessage(error))
    case Done{+selected}: supportedGrammar(stream, callback, fetch, signal, urlContext, model, context, options, timestamp, agent, compat, retention, selected, Request.grammarIssue(selected))

def contextMessages(context: Context()) -> List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>:
  match context:
    case Ai.TranscriptContext{messages}: messages

# upstream stream: the transcript resolved for the model's mid-conversation
# support, grammar tool input properties, cache retention, then buildParams.
def exchange(stream: Stream(), callback: Client.Events(Unit), fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), urlContext: URL.Context, +model: Ai.Model<Ai.JsonValue>, context: Context(), +options: Completions(), timestamp: F64) -> IO(Unit):
  +compat = Request.getCompat(model)
  +normalized = Transcript.resolveTranscript(V.Value, V.Value, Unit, Details(), context, Some{Request.supportsMidConvoSystemMessages(compat)})
  +shared = base(options)
  do IO<Unit>:
    agent : String <- IO.try(String, UserAgent.get())
    retention : Ai.CacheRetention <- Request.resolveCacheRetention(retentionOf(shared), envOf(shared))
    grammarResolved(stream, callback, fetch, signal, urlContext, model, normalized, options, timestamp, agent, compat, retention, Sampling.createGrammarToolInputProperties(Some{Transcript.getDeclaredTools(V.Value, V.Value, Unit, Details(), contextMessages(normalized))}, Request.supportsOpenAIGrammarTools(compat)))

def borrowed(+stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), options: Completions(), timestamp: F64, pair: Deadline.Scope<Unit> & Fetch.Signal(Unit)) -> IO(Unit):
  match pair:
    case (owned, signal):
      do IO<Unit>:
        +callback : Client.Events(Unit) <- C.create(~Stream(), ~Ai.AssistantMessageEvent<V.Value, Unit>, ~Unit, ~pushEvent, stream)
        exchange(stream, callback, fetch, signal, urlContext, model, context, options, timestamp)
        C.dispose(Ai.AssistantMessageEvent<V.Value, Unit>, Unit, callback)
        closed : Maybe<&2, Abort.AbortReason<Deadline.Cause<Unit>>> <- Deadline.close(Unit, owned)
        Events.end(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, stream, None{})

def scoped(stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), options: Completions(), timestamp: F64, scope: Deadline.Scope<Unit>) -> IO(Unit):
  borrowed(stream, fetch, urlContext, model, context, options, timestamp, Deadline.borrow(Unit, scope))

def disposeLocal(local: Maybe<&2, Abort.AbortController<Unit>>) -> IO(Unit):
  match local:
    case None{}: IO.pure(Unit, Unit{})
    case Some{controller}: Abort.dispose(Unit, controller)

def started(stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), +options: Completions(), timestamp: F64, parent: Abort.AbortSignal<Unit>, local: Maybe<&2, Abort.AbortController<Unit>>) -> IO(Unit):
  do IO<Unit>:
    scope : Deadline.Scope<Unit> <- Deadline.create(Unit, timeout(base(options)), parent)
    scoped(stream, fetch, urlContext, model, context, options, timestamp, scope)
    disposeLocal(local)

def producerWith(stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), options: Completions(), timestamp: F64, parent: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Unit):
  match parent:
    case Some{signal}: started(stream, fetch, urlContext, model, context, options, timestamp, signal, None{})
    case None{}:
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        started(stream, fetch, urlContext, model, context, options, timestamp, Abort.signal(Unit, controller), Some{controller})

def producer(stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), +options: Completions(), timestamp: F64) -> IO(Unit):
  producerWith(stream, fetch, urlContext, model, context, options, timestamp, signalOf(base(options)))

def release(stream: Stream(), task: Chan(Unit)) -> IO(Result<&2, &2, Error(), Unit>):
  do IO<Result<&2, &2, Error(), Unit>>:
    finished : Unit <- IO.join(Unit, task)
    Events.disposeAssistantMessageEventStream(V.Value, Unit, stream)
    return Done{Unit{}}

# upstream stream.
def openStream(fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), options: Completions()) -> IO(Output()):
  do IO<Output()>:
    +events : Stream() <- Events.createAssistantMessageEventStream(~V.Value, ~Unit)
    timestamp : F64 <- Date.now()
    task : Chan(Unit) <- IO.fork(Unit, producer(events, fetch, urlContext, model, context, options, timestamp))
    return Done{Agent.StreamLease{events, release(events, task)}}

# upstream streamSimple.
def open(fetch: Fetch.Fetch(Unit), urlContext: URL.Context, +model: Ai.Model<Ai.JsonValue>, +context: Context(), options: Maybe<&2, Options()>) -> IO(Output()):
  openStream(fetch, urlContext, model, context, Request.streamSimpleOptions(~Unit, ~Details(), ~Abort.AbortSignal<Unit>, ~Unit, ~Fetch.Fetch(Unit), ~Error(), model, context, Some{resolvedOptions(options)}))
