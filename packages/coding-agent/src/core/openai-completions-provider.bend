import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/api/openai-completions.bend as Request
import ../../../ai/src/api/openai-completions-client.bend as Client
import ../../../ai/src/api/openai-client.bend as SDK
import ../../../ai/src/api/constrained-sampling.bend as Sampling
import ../../../ai/src/api/github-copilot-headers.bend as Copilot
import ../../../ai/src/api/openai-completions-stream.bend as Fold
import ../../../ai/src/utils/transcript.bend as Transcript
import ../../../ai/src/utils/event-stream.bend as Events
import ../../../agent/src/types.bend as Agent
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/pi-user-agent.bend as UserAgent
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

def fetchOf(value: Base()) -> Maybe<&2, Fetch.Fetch(Unit)>:
  match value:
    case Ai.StreamOptions{_, _, _, fetch, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: fetch

def responseHookOf(value: Base()) -> Maybe<&2, Ai.ResponseCallback(Ai.Model<Ai.JsonValue>, Error())>:
  match value:
    case Ai.StreamOptions{_, _, _, _, _, _, hook, _, _, _, _, _, _, _, _, _, _, _, _}: hook

def resolvedOptions(value: Maybe<&2, Options()>) -> Options():
  match value:
    case None{}: Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error())
    case Some{selected}: selected

def contextMessages(context: Context()) -> List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>:
  match context:
    case Ai.TranscriptContext{messages}: messages

def paramsText(result: Request.ParamsResult()) -> Result<&2, &2, String, Ai.JsonValue>:
  match result:
    case Fail{error}: Fail{Sampling.errorMessage(error)}
    case Done{payload}: Done{payload}

def modelHeaders(model: Ai.Model<Ai.JsonValue>) -> Maybe<&2, R.Record<String>>:
  match model:
    case Ai.Model{_, _, _, _, _, _, _, _, _, _, _, _, _, _, headers, _}: headers

# The grammar properties' failure is thrown by upstream before buildParams.
def built(+model: Ai.Model<Ai.JsonValue>, +normalized: Context(), options: Completions(), +compat: Request.Compat(), retention: Ai.CacheRetention, properties: Result<&2, &2, Sampling.Error, R.Record<String>>) -> IO(Result<&2, &2, String, Ai.JsonValue>):
  match properties:
    case Fail{error}: IO.pure(Result<&2, &2, String, Ai.JsonValue>, Fail{Sampling.errorMessage(error)})
    case Done{selected}:
      do IO<Result<&2, &2, String, Ai.JsonValue>>:
        params : Request.ParamsResult() <- Request.buildParams(~Unit, ~Details(), ~Abort.AbortSignal<Unit>, ~Unit, ~Fetch.Fetch(Unit), ~Error(), model, normalized, options, compat, retention, selected)
        return paramsText(params)

def grammarOf(+normalized: Context(), +compat: Request.Compat()) -> Result<&2, &2, Sampling.Error, R.Record<String>>:
  Sampling.createGrammarToolInputProperties(Some{Transcript.getDeclaredTools(V.Value, V.Value, Unit, Details(), contextMessages(normalized))}, Request.supportsOpenAIGrammarTools(compat))

def propertiesOrEmpty(value: Result<&2, &2, Sampling.Error, R.Record<String>>) -> R.Record<String>:
  match value:
    case Done{properties}: properties
    case Fail{_}: R.new(String)

def launched(+stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, +model: Ai.Model<Ai.JsonValue>, timestamp: F64, +signal: Abort.AbortSignal<Unit>, +compat: Request.Compat(), +shared: Base(), grammar: Result<&2, &2, Sampling.Error, R.Record<String>>, +agent: String, retention: Ai.CacheRetention, params: Result<&2, &2, String, Ai.JsonValue>, copilot: Maybe<&2, R.Record<String>>) -> IO(Unit):
  +headers = Client.defaultHeaders(agent, modelHeaders(model), copilot, Request.clientHeaders(compat, Request.cacheSessionId(retention, sessionOf(shared)), headersOf(shared)))
  +settings = {Fold.Settings{model, Request.supportsFinishReason(compat), propertiesOrEmpty(grammar)} : Fold.Settings}
  +plan = {Client.Prepared{Client.getClientApiKey(Ai.modelProvider(model), keyOf(shared), headersOf(shared)), headers, timeoutOf(shared), retriesOf(shared), delayOf(shared), params, payloadHookOf(shared), responseHookOf(shared)} : Client.Prepared<Error()>}
  Client.stream(~Unit, ~Error(), ~Unit, ~Tools.errorMessage, stream, settings, signal, Client.Context{urlContext, SDK.Defaults{agent, R.new(String), None{}, None{}}, Maybe.default(&2, Fetch.Fetch(Unit), fetchOf(shared), fetch)}, timestamp, plan)

# upstream stream: the transcript resolved for the model's mid-conversation
# support, the client key, grammar tool input properties, cache retention,
# the client's headers and buildParams; then the request lifecycle.
def produced(+stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, +model: Ai.Model<Ai.JsonValue>, context: Context(), +options: Completions(), timestamp: F64, +signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  +compat = Request.getCompat(model)
  +normalized = Transcript.resolveTranscript(V.Value, V.Value, Unit, Details(), context, Some{Request.supportsMidConvoSystemMessages(compat)})
  +shared = base(options)
  +grammar = grammarOf(normalized, compat)
  do IO<Unit>:
    +agent : String <- IO.try(String, UserAgent.get())
    +retention : Ai.CacheRetention <- Request.resolveCacheRetention(retentionOf(shared), envOf(shared))
    params : Result<&2, &2, String, Ai.JsonValue> <- built(model, normalized, options, compat, retention, grammar)
    launched(stream, fetch, urlContext, model, timestamp, signal, compat, shared, grammar, agent, retention, params, Copilot.forProvider(V.Value, V.Value, Unit, Details(), Ai.modelProvider(model), contextMessages(normalized)))

def disposeLocal(local: Maybe<&2, Abort.AbortController<Unit>>) -> IO(Unit):
  match local:
    case None{}: IO.pure(Unit, Unit{})
    case Some{controller}: Abort.dispose(Unit, controller)

def producerWith(stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), options: Completions(), timestamp: F64, parent: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Unit):
  match parent:
    case Some{signal}: produced(stream, fetch, urlContext, model, context, options, timestamp, signal)
    case None{}:
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        produced(stream, fetch, urlContext, model, context, options, timestamp, Abort.signal(Unit, controller))
        disposeLocal(Some{controller})

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
