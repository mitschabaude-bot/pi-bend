import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/api/openai-completions.bend as Request
import ../../../ai/src/api/openai-completions-client.bend as Client
import ../../../ai/src/api/openai-completions-stream.bend as Fold
import ../../../ai/src/api/simple-options.bend as Simple
import ../../../ai/src/utils/thinking-levels.bend as Levels
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

def outputTokens(+model: Ai.Model<Ai.JsonValue>, context: Context(), requested: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match model:
    case Ai.Model{_, _, _, _, _, _, _, _, _, _, _, _, maximum, _, _, _}:
      Some{Simple.clampMaxTokensToContext(~Unit, ~Details(), ~Ai.JsonValue, model, context, Maybe.default(&2, F64, requested, maximum))}

def mappedValue(selected: Ai.ModelThinkingLevel, value: Maybe<&2, Ai.Nullable<String>>) -> Maybe<&2, String>:
  match value:
    case Some{Ai.NullValue{}}: None{}
    case Some{Ai.PresentValue{name}}: Some{name}
    case None{}: Some{Levels.name(selected)}

def mappedEffort(mapping: Maybe<&2, Ai.ThinkingLevelMap>, +selected: Ai.ModelThinkingLevel) -> Maybe<&2, String>:
  mappedValue(selected, Levels.mapped(mapping, selected))

def effortFor(model: Ai.Model<Ai.JsonValue>, selected: Ai.ModelThinkingLevel) -> Maybe<&2, String>:
  match model selected:
    case Ai.Model{_, _, _, _, _, _, mapping, _, _, _, _, _, _, _, _, _} Ai.Off{}: None{}
    case Ai.Model{_, _, _, _, _, _, mapping, _, _, _, _, _, _, _, _, _} level: mappedEffort(mapping, level)

def reasoningFor(+model: Ai.Model<Ai.JsonValue>, level: Ai.ThinkingLevel) -> Maybe<&2, String>:
  match model:
    case Ai.Model{_, _, _, _, _, reasoning, mapping, _, _, _, _, _, _, _, _, _}:
      +selected = Levels.closest(Levels.available(reasoning, mapping), Levels.rank(Ai.Thinking{level}), Ai.Off{})
      effortFor(model, selected)

def reasoningEffort(model: Ai.Model<Ai.JsonValue>, requested: Maybe<&2, Ai.ThinkingLevel>) -> Maybe<&2, String>:
  match requested:
    case None{}: None{}
    case Some{level}: reasoningFor(model, level)

def modelSampling(model: Ai.Model<Ai.JsonValue>) -> Maybe<&2, R.Record<Ai.JsonValue>>:
  match model:
    case Ai.Model{_, _, _, _, _, _, _, _, _, _, _, _, _, sampling, _, _}: sampling

def requestOptions(+model: Ai.Model<Ai.JsonValue>, context: Context(), value: Options()) -> Request.Options:
  match value:
    case Ai.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, temperature, sampling, maxTokens, _, _, _, _, _, choice, +level, _, _}:
      Request.Options{outputTokens(model, context, maxTokens), temperature, choice, reasoningEffort(model, level), Maybe.is_some(&2, Ai.ThinkingLevel, level), Simple.mergeSampling(Ai.JsonValue, modelSampling(model), sampling)}

def requestKey(value: Options()) -> Maybe<&2, String>:
  match value:
    case Ai.SimpleStreamOptions{_, _, key, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: key

def requestHeaders(value: Options()) -> Maybe<&2, Ai.ProviderHeaders()>:
  match value:
    case Ai.SimpleStreamOptions{_, _, _, _, _, _, _, headers, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: headers

def retryCount(value: Options()) -> Maybe<&2, F64>:
  match value:
    case Ai.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, retries, _, _, _, _, _, _, _, _, _, _, _, _, _}: retries

def retryDelay(value: Options()) -> Maybe<&2, F64>:
  match value:
    case Ai.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, delay, _, _, _, _, _, _, _, _, _, _, _, _}: delay

def parentSignal(value: Options()) -> Maybe<&2, Abort.AbortSignal<Unit>>:
  match value:
    case Ai.SimpleStreamOptions{signal, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: signal

def timeoutNumber(value: Result<&2, &2, F.Error, Nat>) -> U32:
  match value:
    case Done{number}: U32.from_nat(Nat.min(4294967295n, number))
    case Fail{_}: 600000

def timeout(value: Options()) -> U32:
  match value:
    case Ai.SimpleStreamOptions{_, _, _, _, _, _, _, _, None{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: 600000
    case Ai.SimpleStreamOptions{_, _, _, _, _, _, _, _, Some{milliseconds}, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      timeoutNumber(F.convert(F.truncate(milliseconds)))

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

def exchange(stream: Stream(), callback: Client.Events(Unit), fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), urlContext: URL.Context, +model: Ai.Model<Ai.JsonValue>, +context: Context(), +options: Options(), timestamp: F64) -> IO(Unit):
  do IO<Unit>:
    agent : String <- IO.try(String, UserAgent.get())
    prepared(stream, callback, fetch, signal, model, timestamp, retryCount(options), retryDelay(options), Ai.onPayloadOption(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error(), options), Client.prepare(Unit, urlContext, model, Request.params(Unit, Details(), model, context, requestOptions(model, context, options), Request.behavior(model)), requestKey(options), agent, requestHeaders(options)))

def borrowed(+stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), options: Options(), timestamp: F64, pair: Deadline.Scope<Unit> & Fetch.Signal(Unit)) -> IO(Unit):
  match pair:
    case (owned, signal):
      do IO<Unit>:
        +callback : Client.Events(Unit) <- C.create(~Stream(), ~Ai.AssistantMessageEvent<V.Value, Unit>, ~Unit, ~pushEvent, stream)
        exchange(stream, callback, fetch, signal, urlContext, model, context, options, timestamp)
        C.dispose(Ai.AssistantMessageEvent<V.Value, Unit>, Unit, callback)
        closed : Maybe<&2, Abort.AbortReason<Deadline.Cause<Unit>>> <- Deadline.close(Unit, owned)
        Events.end(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, stream, None{})

def scoped(stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), options: Options(), timestamp: F64, scope: Deadline.Scope<Unit>) -> IO(Unit):
  borrowed(stream, fetch, urlContext, model, context, options, timestamp, Deadline.borrow(Unit, scope))

def disposeLocal(local: Maybe<&2, Abort.AbortController<Unit>>) -> IO(Unit):
  match local:
    case None{}: IO.pure(Unit, Unit{})
    case Some{controller}: Abort.dispose(Unit, controller)

def started(stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), +options: Options(), timestamp: F64, parent: Abort.AbortSignal<Unit>, local: Maybe<&2, Abort.AbortController<Unit>>) -> IO(Unit):
  do IO<Unit>:
    scope : Deadline.Scope<Unit> <- Deadline.create(Unit, timeout(options), parent)
    scoped(stream, fetch, urlContext, model, context, options, timestamp, scope)
    disposeLocal(local)

def producerWith(stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), options: Options(), timestamp: F64, parent: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Unit):
  match parent:
    case Some{signal}: started(stream, fetch, urlContext, model, context, options, timestamp, signal, None{})
    case None{}:
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        started(stream, fetch, urlContext, model, context, options, timestamp, Abort.signal(Unit, controller), Some{controller})

def producer(stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), +options: Options(), timestamp: F64) -> IO(Unit):
  producerWith(stream, fetch, urlContext, model, context, options, timestamp, parentSignal(options))

def release(stream: Stream(), task: Chan(Unit)) -> IO(Result<&2, &2, Error(), Unit>):
  do IO<Result<&2, &2, Error(), Unit>>:
    finished : Unit <- IO.join(Unit, task)
    Events.disposeAssistantMessageEventStream(V.Value, Unit, stream)
    return Done{Unit{}}

def open(fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), options: Maybe<&2, Options()>) -> IO(Output()):
  do IO<Output()>:
    +events : Stream() <- Events.createAssistantMessageEventStream(~V.Value, ~Unit)
    timestamp : F64 <- Date.now()
    task : Chan(Unit) <- IO.fork(Unit, producer(events, fetch, urlContext, model, context, resolvedOptions(options), timestamp))
    return Done{Agent.StreamLease{events, release(events, task)}}
