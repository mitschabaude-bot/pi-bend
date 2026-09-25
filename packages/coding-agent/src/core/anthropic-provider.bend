import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/api/anthropic-messages.bend as Messages
import ../../../ai/src/api/anthropic-messages-client.bend as Client
import ../../../ai/src/api/anthropic-messages-stream.bend as Fold
import ../../../ai/src/api/simple-options.bend as Simple
import ../../../ai/src/utils/event-stream.bend as Events
import ../../../agent/src/types.bend as Agent
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/url.bend as URL
import ./tools/index.bend as Tools

# Bridge the native Messages exchange to the agent's borrowed event stream.
# The worker owns one request; release joins it before disposing the stream.
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

def toolChoice(value: Maybe<&2, Ai.ToolChoice>) -> Maybe<&2, Messages.ToolChoice>:
  match value:
    case None{}: None{}
    case Some{Ai.AutoTool{}}: Some{Messages.Auto{}}
    case Some{Ai.NoTool{}}: Some{Messages.NoneChoice{}}

def levelName(level: Ai.ThinkingLevel) -> String:
  match level:
    case Ai.Minimal{}: "low"
    case Ai.Low{}: "low"
    case Ai.Medium{}: "medium"
    case Ai.High{}: "high"
    case Ai.XHigh{}: "xhigh"
    case Ai.Max{}: "max"

def adaptive(model: Ai.Model<Ai.JsonValue>) -> Bool:
  match model:
    case Ai.Model{_, _, Ai.AnthropicMessagesApi{}, _, _, _, _, _, _, _, _, _, _, _, _, Some{Ai.AnthropicMessagesCompat{_, _, _, _, _, _, Some{True{}}, _, _, _, _, _, _}}}: True{}
    case _: False{}

def thoughtKind(level: Ai.ThinkingLevel, budgets: Maybe<&2, Ai.ThinkingBudgets>, adaptiveModel: Bool) -> Messages.Thinking:
  match adaptiveModel:
    case True{}: Messages.AdaptiveThinking{Some{levelName(level)}, "summarized"}
    case False{}: Messages.BudgetThinking{Simple.thinkingBudgetForLevel(level, budgets), "summarized"}

# upstream streamSimple: without a reasoning level thinking is disabled.
def thought(level: Maybe<&2, Ai.ThinkingLevel>, budgets: Maybe<&2, Ai.ThinkingBudgets>, adaptiveModel: Bool) -> Messages.Thinking:
  match level:
    case None{}: Messages.DisabledThinking{}
    case Some{value}: thoughtKind(value, budgets, adaptiveModel)

def retention(value: Maybe<&2, Ai.CacheRetention>) -> Ai.CacheRetention:
  match value:
    case None{}: Ai.CacheShort{}
    case Some{selected}: selected

def oauth(key: Maybe<&2, String>) -> Bool:
  match key:
    case None{}: False{}
    case Some{value}: String.contains(value, "sk-ant-oat")

def requestOptions(model: Ai.Model<Ai.JsonValue>, value: Options()) -> Messages.Options:
  match value:
    case Ai.SimpleStreamOptions{_, _, key, _, _, _, _, _, _, _, _, temperature, _, maxTokens, _, cache, _, _, _, choice, reasoning, _, budgets}:
      Messages.Options{maxTokens, temperature, thought(reasoning, budgets, adaptive(model)), toolChoice(choice), retention(cache), oauth(key)}

def requestKey(value: Options()) -> Maybe<&2, String>:
  match value:
    case Ai.SimpleStreamOptions{_, _, key, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: key

def requestHeaders(+model: Ai.Model<Ai.JsonValue>, value: Options()) -> Maybe<&2, Ai.ProviderHeaders()>:
  match value:
    case Ai.SimpleStreamOptions{_, _, key, _, _, _, _, headers, _, _, _, _, _, _, _, _, sessionId, _, _, _, _, _, _}: Messages.clientHeaders(model, sessionId, oauth(key), headers)

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

def prepared(stream: Stream(), callback: Client.Events(Unit), fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), model: Ai.Model<Ai.JsonValue>, timestamp: F64, value: Result<&2, &2, Client.Error<Unit>, Client.Request>) -> IO(Unit):
  match value:
    case Fail{_}: pushFailure(stream, model, timestamp, "Could not prepare Anthropic request")
    case Done{request}:
      do IO<Unit>:
        result : Result<&2, &2, Client.Error<Unit>, Ai.AssistantMessage<V.Value, Unit>> <- Client.run(~Unit, ~Unit, fetch, signal, callback, model, request, timestamp)
        return Unit{}

def exchange(stream: Stream(), callback: Client.Events(Unit), fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), urlContext: URL.Context, +model: Ai.Model<Ai.JsonValue>, context: Context(), +options: Options(), timestamp: F64) -> IO(Unit):
  prepared(stream, callback, fetch, signal, model, timestamp, Client.prepare(Unit, Unit, Details(), urlContext, model, context, requestOptions(model, options), requestKey(options), requestHeaders(model, options)))

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
