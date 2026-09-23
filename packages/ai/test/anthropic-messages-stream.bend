import Base
import ../src/api/anthropic-messages-stream.bend as Anthropic
import ../src/providers/anthropic.models.bend as Models
import ../src/types.bend as T
import ../../runtime/src/f64.bend as F
import ../../runtime/src/json.bend as Json
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V

def model() -> T.Model<T.JsonValue>: Models.model_claude_opus_5()

def eventName(-G: Data, event: T.AssistantMessageEvent<V.Value, G>) -> String:
  match event:
    case T.Start{_}: "start"
    case T.TextStart{_, _}: "text_start"
    case T.TextDelta{_, _, _}: "text_delta"
    case T.TextEnd{_, _, _}: "text_end"
    case T.ThinkingStart{_, _}: "thinking_start"
    case T.ThinkingDelta{_, _, _}: "thinking_delta"
    case T.ThinkingEnd{_, _, _}: "thinking_end"
    case T.ToolcallStart{_, _}: "toolcall_start"
    case T.ToolcallDelta{_, _, _}: "toolcall_delta"
    case T.ToolcallEnd{_, _, _}: "toolcall_end"
    case T.StreamDone{_, _}: "done"
    case T.StreamError{_, _}: "error"

def names(events: List<&2, T.AssistantMessageEvent<V.Value, Unit>>) -> List<&2, String>:
  match events:
    case Nil{}: Nil{}
    case event <> rest: eventName(Unit, event) <> names(rest)

def stateOf(result: Anthropic.Step<Unit>) -> Anthropic.State<Unit>:
  match result:
    case Anthropic.Step{next, _, _}: next

def namesOf(result: Anthropic.Step<Unit>) -> List<&2, String>:
  match result:
    case Anthropic.Step{_, emitted, _}: names(emitted)

@unsafe def fold(pair: Anthropic.Step<Unit> & List<&2, V.Value>, observed: List<&2, String>) -> Anthropic.State<Unit> & List<&2, String>:
  match pair:
    case (Anthropic.Step{state, emitted, Some{_}}, _): (state, List.append(&2, String, observed, names(emitted)))
    case (Anthropic.Step{state, emitted, None{}}, Nil{}):
      +final = Anthropic.finish(Unit, state)
      (stateOf(final), List.append(&2, String, List.append(&2, String, observed, names(emitted)), namesOf(final)))
    case (Anthropic.Step{state, emitted, None{}}, event <> rest):
      fold((Anthropic.event(Unit, state, event, model()), rest), List.append(&2, String, observed, names(emitted)))

def signatureText(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: ""
    case Some{text}: text

def content(values: List<&2, T.AssistantContent<V.Value>>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case T.AssistantText{T.TextContent{value, _}} <> rest: ("text:" ++ value) <> content(rest)
    case T.AssistantThinking{T.ThinkingContent{value, signature, _}} <> rest: ("thinking:" ++ value ++ ":" ++ signatureText(signature)) <> content(rest)
    case T.AssistantToolCall{T.ToolCall{id, name, _, _, _}} <> rest: ("tool:" ++ id ++ ":" ++ name) <> content(rest)

def strings(items: List<&2, String>) -> List<&2, V.Value>:
  match items:
    case Nil{}: Nil{}
    case value <> rest: V.Text{value} <> strings(rest)

def array(items: List<&2, String>) -> V.Value:
  V.ArrayValue{strings(items)}

def maybeText(value: Maybe<&2, String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{text}: V.Text{text}

def reasonName(value: T.StopReason) -> String:
  match value:
    case T.Stop{}: "stop"
    case T.Length{}: "length"
    case T.ToolUse{}: "toolUse"
    case T.Pending{}: "pending"
    case _: "error"

def summary(result: Anthropic.State<Unit> & List<&2, String>) -> V.Value:
  match result:
    case Tuple{Anthropic.State{T.AssistantMessage{blocks, _, _, _, responseModel, responseId, _, _, T.Usage{input, output, _, _, _, _, total, _}, reason, _, errorMessage, _, _, _}, _, _, _}, events}:
      V.ObjectValue{R.Record{R.Property{"events", array(events)} <> R.Property{"content", array(content(blocks))} <> R.Property{"responseModel", maybeText(responseModel)} <> R.Property{"responseId", maybeText(responseId)} <> R.Property{"input", V.Number{input}} <> R.Property{"output", V.Number{output}} <> R.Property{"total", V.Number{total}} <> R.Property{"reason", V.Text{reasonName(reason)}} <> R.Property{"errorMessage", maybeText(errorMessage)} <> Nil{}}}

def check(input: Result<&2, &2, Json.ParseError, V.Value>, expected: Result<&2, &2, Json.ParseError, V.Value>) -> IO(Unit):
  match input expected:
    case Done{V.ArrayValue{events}} Done{wanted}:
      +actual = summary(fold((Anthropic.Step{Anthropic.create(Unit, model(), F.fromU32(1)), Nil{}, None{}}, events), Nil{}))
      Bool.pick(IO(Unit), V.equal(actual, wanted), IO.print("PASS Anthropic SSE"), IO.die(Unit, 1, "Anthropic SSE mismatch"))
    case _ _: IO.die(Unit, 1, "invalid fixture")

def run(args: List<String>) -> IO(Unit):
  match args:
    case events <> expected <> Nil{}: check(Json.parse(events), Json.parse(expected))
    case _: IO.die(Unit, 1, "expected event and summary JSON")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
