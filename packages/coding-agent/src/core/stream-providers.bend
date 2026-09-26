import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/api/pi-messages.bend as PiMessages
import ../../../ai/src/utils/event-stream.bend as Events
import ../../../agent/src/types.bend as Agent
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/url.bend as URL
import ./tools/index.bend as Tools

# The agent's stream functions for the APIs whose modules stream into an
# event stream themselves (upstream `stream`/`streamSimple` returning an
# AssistantMessageEventStream): a worker runs the request under the
# caller's signal, or a local one, and ends the stream; release joins it
# before disposing the stream.
def Details() -> Data: Tools.ToolDetails
def Error() -> Data: Tools.ToolError
def Options() -> Data: Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>
def Context() -> Data: Ai.TranscriptContext<V.Value, V.Value, Unit, Details()>
def Stream() -> Data: Events.AssistantMessageEventStream(V.Value, Unit)
def Output() -> Type: Result<&2, &1, Error(), Agent.StreamLease<Unit, Error()>>
def Producer() -> Type: Stream() -> Abort.AbortSignal<Unit> -> IO(Unit)

# The CLI's assistant messages carry no diagnostic details.
def noDetails(value: Ai.JsonValue) -> Unit: Unit{}
def unitDetails(value: Unit) -> V.Value: V.Null{}

def parentSignal(options: Maybe<&2, Options()>) -> Maybe<&2, Abort.AbortSignal<Unit>>:
  match options:
    case Some{Ai.SimpleStreamOptions{signal, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: signal
    case None{}: None{}

def signalled(+events: Stream(), produce: Producer(), parent: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Unit):
  match parent:
    case Some{signal}: produce(events, signal)
    case None{}:
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        produce(events, Abort.signal(Unit, controller))
        Abort.dispose(Unit, controller)

def worker(+events: Stream(), produce: Producer(), parent: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Unit):
  do IO<Unit>:
    signalled(events, produce, parent)
    Events.end(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, events, None{})

def release(stream: Stream(), task: Chan(Unit)) -> IO(Result<&2, &2, Error(), Unit>):
  do IO<Result<&2, &2, Error(), Unit>>:
    finished : Unit <- IO.join(Unit, task)
    Events.disposeAssistantMessageEventStream(V.Value, Unit, stream)
    return Done{Unit{}}

def lease(produce: Producer(), parent: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Output()):
  do IO<Output()>:
    +events : Stream() <- Events.createAssistantMessageEventStream(~V.Value, ~Unit)
    task : Chan(Unit) <- IO.fork(Unit, worker(events, produce, parent))
    return Done{Agent.StreamLease{events, release(events, task)}}

# upstream pi-messages streamSimple.
def piMessages(fetch: Fetch.Fetch(Unit), urlContext: URL.Context, model: Ai.Model<Ai.JsonValue>, context: Context(), +options: Maybe<&2, Options()>) -> IO(Output()):
  lease(events => signal => PiMessages.streamSimple(~Unit, ~Unit, ~Error(), ~Unit, ~Details(), ~Tools.errorMessage, ~noDetails, ~unitDetails, ~Tools.detailsValue, events, fetch, urlContext, signal, model, context, options, None{}), parentSignal(options))
