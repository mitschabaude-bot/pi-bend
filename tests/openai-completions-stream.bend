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
import ../packages/runtime/src/json.bend as Decode
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/test/utf8-runner.bend as Text
import ./openai-completions-request.bend as Fixture

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

@unsafe def drain(next: Events.Iteration<StreamEvent()>, +cursor: Events.Iterator<StreamEvent(), Message()>, reversed: List<&2, V.Value>) -> IO(List<&2, V.Value>):
  match next:
    case Events.Yield{event}:
      do IO<List<&2, V.Value>>:
        following : Events.Iteration<StreamEvent()> <- Events.nextValue(StreamEvent(), Message(), cursor)
        drain(following, cursor, eventJson(event) <> reversed)
    case Events.End{}:
      do IO<List<&2, V.Value>>:
        Events.disposeIterator(StreamEvent(), Message(), cursor)
        return List.reverse(&2, V.Value, reversed)

def report(events: List<&2, V.Value>, message: Message()) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"events", V.ArrayValue{events}} <> R.Property{"message", MessageJson.assistantMessage(~Unit, ~noDetails, message)} <> Nil{}}}

def consumed(output: Output()) -> IO(V.Value):
  match output:
    case Fail{_}: IO.pure(V.Value, V.Text{"provider failed to open"})
    case Done{Agent.StreamLease{+events, release}}:
      do IO<V.Value>:
        +cursor : Events.Iterator<StreamEvent(), Message()> <- Events.iterator(StreamEvent(), Message(), events)
        first : Events.Iteration<StreamEvent()> <- Events.nextValue(StreamEvent(), Message(), cursor)
        values : List<&2, V.Value> <- drain(first, cursor, Nil{})
        message : Message() <- Events.resultValue(StreamEvent(), Message(), events)
        result : Result<&2, &2, Error(), Unit> <- release
        return report(values, message)

def opened(+entry: String, +fetch: Fetch.Fetch(Unit), +value: V.Value) -> IO(Output()):
  match entry:
    case "stream": Completions.openStream(fetch, Fixture.urls(), Fixture.model(value), Fixture.context(value), Fixture.streamOptions(Fixture.settings(value), Some{fetch}))
    case _: Completions.open(fetch, Fixture.urls(), Fixture.model(value), Fixture.context(value), Some{Fixture.simpleOptions(Fixture.settings(value), fetch)})

def shown(value: V.Value) -> String:
  Maybe.default(&2, String, Wire.stringify(Convert.toJson(value)), "null")

def run(+fetch: Fetch.Fetch(Unit), result: Result<&2, &2, Decode.ParseError, V.Value>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("R " ++ Text.showText("{\"error\":\"invalid case\"}"))
    case Done{+value}:
      do IO<Unit>:
        output : Output() <- opened(Maybe.default(&2, String, Fixture.text(Fixture.field(value, "entry")), "simple"), fetch, value)
        reported : V.Value <- consumed(output)
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
