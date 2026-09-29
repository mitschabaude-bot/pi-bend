import Base
import ../src/core/anthropic-provider.bend as Anthropic
import ../src/core/tools/index.bend as Tools
import ../../ai/test/anthropic-messages-client.bend as TestClient
import ../../ai/src/types.bend as Ai
import ../../agent/src/types.bend as Agent
import ../../ai/src/utils/event-stream.bend as Events
import ../../runtime/src/callback.bend as C
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../ai/src/utils/json.bend as Json
import ../../ai/src/utils/schema-json.bend as SchemaJson
import ../../ai/src/utils/message-json.bend as MessageJson

def eventName(event: Ai.AssistantMessageEvent<V.Value, V.Value>) -> String:
  match event:
    case Ai.Start{_}: "start"
    case Ai.TextStart{_, _}: "text_start"
    case Ai.TextDelta{_, _, _}: "text_delta"
    case Ai.TextEnd{_, _, _}: "text_end"
    case Ai.ThinkingStart{_, _}: "thinking_start"
    case Ai.ThinkingDelta{_, _, _}: "thinking_delta"
    case Ai.ThinkingEnd{_, _, _}: "thinking_end"
    case Ai.ToolcallStart{_, _}: "toolcall_start"
    case Ai.ToolcallDelta{_, _, _}: "toolcall_delta"
    case Ai.ToolcallEnd{_, _, _}: "toolcall_end"
    case Ai.StreamDone{_, _}: "done"
    case Ai.StreamError{_, _}: "error"
    case _: "other"
def raw(value: V.Value) -> V.Value: value

def context() -> Anthropic.Context():
  Ai.TranscriptContext{Ai.User{Ai.UserMessage{Ai.UserText{"ping"}, F.fromU32(1)}} <> Nil{}}

def schema() -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"value", V.ObjectValue{R.Record{R.Property{"type", V.Text{"string"}} <> Nil{}}}} <> Nil{}}}} <> Nil{}}}

def system() -> Ai.SystemMessage<V.Value>:
  Ai.SystemMessage{Ai.SystemText{"Use the lookup tool."}, None{}, Some{Ai.Tool{"lookup", "Look up a value", schema(), None{}} <> Nil{}}, None{}, F.fromU32(1)}

def toolContext() -> Anthropic.Context():
  Ai.TranscriptContext{Ai.System{system()} <> Ai.User{Ai.UserMessage{Ai.UserText{"lookup 42"}, F.fromU32(2)}} <> Nil{}}

def continued(first: Ai.AssistantMessage<V.Value, V.Value>) -> Anthropic.Context():
  Ai.TranscriptContext{Ai.System{system()} <> Ai.User{Ai.UserMessage{Ai.UserText{"lookup 42"}, F.fromU32(2)}} <> Ai.Assistant{first} <> Ai.ToolResult{Ai.ToolResultMessage{"toolu_1", "lookup", Ai.TextImageText{Ai.TextContent{"found 42", None{}}} <> Nil{}, None{}, None{}, False{}, F.fromU32(3)}} <> Nil{}}

def options() -> Anthropic.Options():
  Ai.withApiKey(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Anthropic.Error(), Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Anthropic.Error()), Some{"test-key"})

@unsafe def drain(next: Events.Iteration<Ai.AssistantMessageEvent<V.Value, V.Value>>, +cursor: Events.Iterator<Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>>) -> IO(Unit):
  match next:
    case Events.Yield{event}:
      do IO<Unit>:
        IO.print(eventName(event))
        following : Events.Iteration<Ai.AssistantMessageEvent<V.Value, V.Value>> <- Events.nextValue(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, cursor)
        drain(following, cursor)
    case Events.End{}: Events.disposeIterator(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, cursor)

def opened(result: Anthropic.Output()) -> IO(Ai.AssistantMessage<V.Value, V.Value>):
  match result:
    case Fail{_}: IO.die(Ai.AssistantMessage<V.Value, V.Value>, 1, "provider failed to open")
    case Done{Agent.StreamLease{+events, release}}:
      do IO<Ai.AssistantMessage<V.Value, V.Value>>:
        +cursor : Events.Iterator<Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>> <- Events.iterator(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, events)
        first : Events.Iteration<Ai.AssistantMessageEvent<V.Value, V.Value>> <- Events.nextValue(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, cursor)
        drain(first, cursor)
        message : Ai.AssistantMessage<V.Value, V.Value> <- Events.resultValue(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, events)
        result : Result<&2, &2, Anthropic.Error(), Unit> <- release
        return message

def request(fetch: Fetch.Fetch(Unit), base: String, context: Anthropic.Context()) -> IO(Ai.AssistantMessage<V.Value, V.Value>):
  do IO<Ai.AssistantMessage<V.Value, V.Value>>:
    result : Anthropic.Output() <- Anthropic.open(fetch, TestClient.urlContext(), TestClient.model(base), context, Some{options()})
    opened(result)

def scenario(+fetch: Fetch.Fetch(Unit), +base: String, mode: String) -> IO(Unit):
  match mode:
    case "diagnostics":
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, V.Value> <- request(fetch, base, context())
        IO.print(Maybe.default(&2, String, Json.stringify(SchemaJson.toJson(MessageJson.assistantMessage(~V.Value, ~raw, message))), ""))
        return Unit{}
    case "tool":
      do IO<Unit>:
        first : Ai.AssistantMessage<V.Value, V.Value> <- request(fetch, base, toolContext())
        second : Ai.AssistantMessage<V.Value, V.Value> <- request(fetch, base, continued(first))
        return Unit{}
    case _:
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, V.Value> <- request(fetch, base, context())
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
