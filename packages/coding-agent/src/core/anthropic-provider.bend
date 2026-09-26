import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/api/anthropic-messages.bend as Messages
import ../../../ai/src/api/anthropic-messages-client.bend as Client
import ../../../ai/src/api/anthropic-messages-stream.bend as Fold
import ../../../ai/src/api/openai-client.bend as SDK
import ../../../ai/src/utils/event-stream.bend as Events
import ../../../agent/src/types.bend as Agent
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/pi-user-agent.bend as UserAgent
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/url.bend as URL
import ./tools/index.bend as Tools

# upstream anthropic-messages streamSimple for the agent: the simple options
# become AnthropicOptions and one worker runs the request lifecycle
# (anthropic-messages-client.bend); release joins it before disposing the
# stream. The app's diagnostic details are Unit, so input transformation
# diagnostics keep their type and timestamp without details.
def Details() -> Data: Tools.ToolDetails
def Error() -> Data: Tools.ToolError
def Options() -> Data: Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>
def Context() -> Data: Ai.TranscriptContext<V.Value, V.Value, Unit, Details()>
def Stream() -> Data: Events.AssistantMessageEventStream(V.Value, Unit)
def Output() -> Type: Result<&2, &1, Error(), Agent.StreamLease<Unit, Error()>>
def Anthropic() -> Data: Client.Options(Unit, Unit, Error())

def signalOf(options: Anthropic()) -> Maybe<&2, Abort.AbortSignal<Unit>>:
  match options:
    case Messages.AnthropicOptions{Ai.StreamOptions{signal, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _, _}: signal

def resolvedOptions(value: Maybe<&2, Options()>) -> Options():
  match value:
    case None{}: Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error())
    case Some{selected}: selected

def noDetails(values: List<&2, Fold.InputTransformation>) -> Unit: Unit{}

def produced(+stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, +model: Ai.Model<Ai.JsonValue>, context: Context(), +options: Anthropic(), timestamp: F64, +signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  do IO<Unit>:
    +agent : String <- IO.try(String, UserAgent.get())
    Client.stream(~Unit, ~Unit, ~Error(), ~Unit, ~noDetails, ~Details(), ~Tools.errorMessage, stream, signal, Client.Setup{urlContext, SDK.Defaults{Client.sdkUserAgent(), R.new(String), None{}, None{}}, agent, fetch}, model, context, options, timestamp)

def disposeLocal(local: Maybe<&2, Abort.AbortController<Unit>>) -> IO(Unit):
  match local:
    case None{}: IO.pure(Unit, Unit{})
    case Some{controller}: Abort.dispose(Unit, controller)

def producerWith(stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), options: Anthropic(), timestamp: F64, parent: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Unit):
  match parent:
    case Some{signal}: produced(stream, fetch, urlContext, model, context, options, timestamp, signal)
    case None{}:
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        produced(stream, fetch, urlContext, model, context, options, timestamp, Abort.signal(Unit, controller))
        disposeLocal(Some{controller})

def producer(stream: Stream(), fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), +options: Anthropic(), timestamp: F64) -> IO(Unit):
  producerWith(stream, fetch, urlContext, model, context, options, timestamp, signalOf(options))

def release(stream: Stream(), task: Chan(Unit)) -> IO(Result<&2, &2, Error(), Unit>):
  do IO<Result<&2, &2, Error(), Unit>>:
    finished : Unit <- IO.join(Unit, task)
    Events.disposeAssistantMessageEventStream(V.Value, Unit, stream)
    return Done{Unit{}}

# upstream stream.
def openStream(fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), options: Anthropic()) -> IO(Output()):
  do IO<Output()>:
    +events : Stream() <- Events.createAssistantMessageEventStream(~V.Value, ~Unit)
    timestamp : F64 <- Date.now()
    task : Chan(Unit) <- IO.fork(Unit, producer(events, fetch, urlContext, model, context, options, timestamp))
    return Done{Agent.StreamLease{events, release(events, task)}}

# upstream streamSimple.
def open(fetch: Fetch.Fetch(Unit), urlContext: URL.Context, +model: Ai.Model<Ai.JsonValue>, +context: Context(), options: Maybe<&2, Options()>) -> IO(Output()):
  openStream(fetch, urlContext, model, context, Messages.streamSimpleOptions(~Unit, ~Details(), ~Abort.AbortSignal<Unit>, ~Unit, ~Fetch.Fetch(Unit), ~Error(), ~Client.AnthropicClient(), model, context, Some{resolvedOptions(options)}))
