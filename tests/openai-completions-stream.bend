import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/json.bend as Wire
import ../packages/ai/src/utils/message-json.bend as MessageJson
import ../packages/ai/src/utils/schema-json.bend as Convert
import ../packages/ai/src/utils/event-stream.bend as Events
import ../packages/ai/test/google-generative-ai-client.bend as Network
import ../packages/agent/src/types.bend as Agent
import ../packages/coding-agent/src/core/openai-completions-provider.bend as Completions
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/json.bend as Decode
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/test/utf8-runner.bend as Text
import ./openai-completions-request.bend as Fixture
import ../packages/ai/src/api/openai-completions.bend as Request

# The Chat Completions stream path against upstream `stream`/`streamSimple`
# over a scripted local HTTP server (tests/openai_completions_stream_check.py).
# Each argument is one JSON case, encoded as comma-separated scalars, in the
# shape tests/openai-completions-request.bend reads ("simple" or "stream").
# The native provider streams through a real fetch runtime; every event and
# the final message are reported as JSON.

def Error() -> Data: Tools.ToolError
def Output() -> Type: Result<&2, &1, Error(), Agent.StreamLease<Unit, Error()>>
def StreamEvent() -> Data: Ai.AssistantMessageEvent<V.Value, Unit>
def Message() -> Data: Ai.AssistantMessage<V.Value, Unit>

def noDetails(value: Unit) -> V.Value: V.Null{}

def eventJson(event: StreamEvent()) -> V.Value: MessageJson.assistantMessageEvent(~Unit, ~noDetails, event)

# `abortAfter` names the event type after whose first occurrence the case
# aborts its request signal, as a caller cancelling mid-stream would.
def triggered(+json: V.Value, trigger: Maybe<&2, String>) -> Bool:
  match trigger:
    case Some{name}: String.eq(Maybe.default(&2, String, Fixture.text(Fixture.field(json, "type")), ""), name)
    case None{}: False{}

def fired(controller: Abort.AbortController<Unit>, fire: Bool) -> IO(Unit):
  match fire:
    case True{}:
      do IO<Unit>:
        done : Bool <- Abort.abort(Unit, controller, None{})
        return Unit{}
    case False{}: IO.pure(Unit, Unit{})

@unsafe def drain(next: Events.Iteration<StreamEvent()>, +cursor: Events.Iterator<StreamEvent(), Message()>, +controller: Abort.AbortController<Unit>, +trigger: Maybe<&2, String>, reversed: List<&2, V.Value>) -> IO(List<&2, V.Value>):
  match next:
    case Events.Yield{event}:
      +json = eventJson(event)
      +fire = triggered(json, trigger)
      do IO<List<&2, V.Value>>:
        fired(controller, fire)
        following : Events.Iteration<StreamEvent()> <- Events.nextValue(StreamEvent(), Message(), cursor)
        drain(following, cursor, controller, Bool.pick(Maybe<&2, String>, fire, None{}, trigger), json <> reversed)
    case Events.End{}:
      do IO<List<&2, V.Value>>:
        Events.disposeIterator(StreamEvent(), Message(), cursor)
        return List.reverse(&2, V.Value, reversed)

def report(events: List<&2, V.Value>, message: Message()) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"events", V.ArrayValue{events}} <> R.Property{"message", MessageJson.assistantMessage(~Unit, ~noDetails, message)} <> Nil{}}}

def consumed(+controller: Abort.AbortController<Unit>, trigger: Maybe<&2, String>, output: Output()) -> IO(V.Value):
  match output:
    case Fail{_}: IO.pure(V.Value, V.Text{"provider failed to open"})
    case Done{Agent.StreamLease{+events, release}}:
      do IO<V.Value>:
        +cursor : Events.Iterator<StreamEvent(), Message()> <- Events.iterator(StreamEvent(), Message(), events)
        first : Events.Iteration<StreamEvent()> <- Events.nextValue(StreamEvent(), Message(), cursor)
        values : List<&2, V.Value> <- drain(first, cursor, controller, trigger, Nil{})
        message : Message() <- Events.resultValue(StreamEvent(), Message(), events)
        result : Result<&2, &2, Error(), Unit> <- release
        return report(values, message)

def signalled(options: Completions.Completions(), signal: Abort.AbortSignal<Unit>) -> Completions.Completions():
  match options:
    case Request.OpenAICompletionsOptions{Ai.StreamOptions{_, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r}, choice, effort, budgets}: Request.OpenAICompletionsOptions{Ai.StreamOptions{Some{signal}, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r}, choice, effort, budgets}

def opened(+entry: String, +fetch: Fetch.Fetch(Unit), +signal: Abort.AbortSignal<Unit>, +value: V.Value) -> IO(Output()):
  match entry:
    case "stream": Completions.openStream(fetch, Fixture.urls(), Fixture.model(value), Fixture.context(value), signalled(Fixture.streamOptions(Fixture.settings(value), Some{fetch}), signal))
    case _: Completions.open(fetch, Fixture.urls(), Fixture.model(value), Fixture.context(value), Some{Ai.withSignal(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error(), Fixture.simpleOptions(Fixture.settings(value), fetch), Some{signal})})

def shown(value: V.Value) -> String:
  Maybe.default(&2, String, Wire.stringify(Convert.toJson(value)), "null")

def run(+fetch: Fetch.Fetch(Unit), result: Result<&2, &2, Decode.ParseError, V.Value>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("R " ++ Text.showText("{\"error\":\"invalid case\"}"))
    case Done{+value}:
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        output : Output() <- opened(Maybe.default(&2, String, Fixture.text(Fixture.field(value, "entry")), "simple"), fetch, Abort.signal(Unit, controller), value)
        reported : V.Value <- consumed(controller, Fixture.text(Fixture.field(value, "abortAfter")), output)
        Abort.dispose(Unit, controller)
        IO.print("R " ++ Text.showText(shown(reported)))

def all(+fetch: Fetch.Fetch(Unit), arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case encoded <> rest:
      do IO<Unit>:
        run(fetch, Decode.parse(Text.fromScalars(Text.parseNumbers(encoded))))
        all(fetch, rest)

def borrowed(arguments: List<String>, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (runtime, +fetch):
      do IO<Unit>:
        all(fetch, arguments)
        Fetch.retire(Unit, fetch)
        Fetch.dispose(runtime)

def initialized(arguments: List<String>, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "network initialization failed")
    case Done{runtime}:
      do IO<Unit>:
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit, runtime)
        borrowed(arguments, pair)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), Network.networkOptions())
    initialized(arguments, runtime)
