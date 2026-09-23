import Base
import ../src/core/google-provider.bend as Google
import ../src/core/tools/index.bend as Tools
import ../../ai/test/google-generative-ai-client.bend as TestClient
import ../../ai/src/types.bend as Ai
import ../../agent/src/types.bend as Agent
import ../../ai/src/utils/event-stream.bend as Events
import ../../runtime/src/callback.bend as C
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R

def context() -> Google.Context():
  Ai.TranscriptContext{Ai.User{Ai.UserMessage{Ai.UserText{"ping"}, F.fromU32(1)}} <> Nil{}}

def schema() -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"value", V.ObjectValue{R.Record{R.Property{"type", V.Text{"string"}} <> Nil{}}}} <> Nil{}}}} <> Nil{}}}

def system() -> Ai.SystemMessage<V.Value>:
  Ai.SystemMessage{Ai.SystemText{"Use the lookup tool."}, None{}, Some{Ai.Tool{"lookup", "Look up a value", schema(), None{}} <> Nil{}}, None{}, F.fromU32(1)}

def toolContext() -> Google.Context():
  Ai.TranscriptContext{Ai.System{system()} <> Ai.User{Ai.UserMessage{Ai.UserText{"lookup 42"}, F.fromU32(2)}} <> Nil{}}

def continued(first: Ai.AssistantMessage<V.Value, Unit>) -> Google.Context():
  Ai.TranscriptContext{Ai.System{system()} <> Ai.User{Ai.UserMessage{Ai.UserText{"lookup 42"}, F.fromU32(2)}} <> Ai.Assistant{first} <> Ai.ToolResult{Ai.ToolResultMessage{"call-1", "lookup", Ai.TextImageText{Ai.TextContent{"found 42", None{}}} <> Nil{}, None{}, None{}, False{}, F.fromU32(3)}} <> Nil{}}

def options() -> Google.Options():
  Ai.withApiKey(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Google.Error(), Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Google.Error()), Some{"test-google-key"})

@unsafe def drain(next: Events.Iteration<Ai.AssistantMessageEvent<V.Value, Unit>>, +cursor: Events.Iterator<Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>>) -> IO(Unit):
  match next:
    case Events.Yield{event}:
      do IO<Unit>:
        IO.print(TestClient.eventName(event))
        following : Events.Iteration<Ai.AssistantMessageEvent<V.Value, Unit>> <- Events.nextValue(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, cursor)
        drain(following, cursor)
    case Events.End{}: Events.disposeIterator(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, cursor)

def opened(result: Google.Output()) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  match result:
    case Fail{_}: IO.die(Ai.AssistantMessage<V.Value, Unit>, 1, "provider failed to open")
    case Done{Agent.StreamLease{+events, release}}:
      do IO<Ai.AssistantMessage<V.Value, Unit>>:
        +cursor : Events.Iterator<Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>> <- Events.iterator(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, events)
        first : Events.Iteration<Ai.AssistantMessageEvent<V.Value, Unit>> <- Events.nextValue(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, cursor)
        drain(first, cursor)
        message : Ai.AssistantMessage<V.Value, Unit> <- Events.resultValue(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, events)
        result : Result<&2, &2, Google.Error(), Unit> <- release
        return message

def request(fetch: Fetch.Fetch(Unit), base: String, context: Google.Context()) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  do IO<Ai.AssistantMessage<V.Value, Unit>>:
    result : Google.Output() <- Google.open(fetch, TestClient.urlContext(), TestClient.model(base), context, Some{options()})
    opened(result)

def scenario(+fetch: Fetch.Fetch(Unit), +base: String, mode: String) -> IO(Unit):
  match mode:
    case "tool":
      do IO<Unit>:
        first : Ai.AssistantMessage<V.Value, Unit> <- request(fetch, base, toolContext())
        second : Ai.AssistantMessage<V.Value, Unit> <- request(fetch, base, continued(first))
        return Unit{}
    case _:
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, Unit> <- request(fetch, base, context())
        return Unit{}

def borrowed(base: String, mode: String, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (runtime, +fetch):
      do IO<Unit>:
        scenario(fetch, base, mode)
        Fetch.retire(Unit, fetch)
        Fetch.dispose(runtime)

def initialized(base: String, mode: String, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "network initialization failed")
    case Done{runtime}:
      do IO<Unit>:
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit, runtime)
        borrowed(base, mode, pair)

def run(base: String, mode: String) -> IO(Unit):
  do IO<Unit>:
    runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), TestClient.networkOptions())
    initialized(base, mode, runtime)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case base <> Nil{}: run(base, "basic")
    case base <> mode <> Nil{}: run(base, mode)
    case _: IO.die(Unit, 1, "base URL required")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
