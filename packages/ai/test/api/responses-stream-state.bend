import Base
import ../../src/api/openai-responses-stream.bend as S
import ../../src/api/constrained-sampling.bend as Sampling
import ../../src/types.bend as T
import ../../src/utils/json.bend as Json
import ../../src/utils/schema-json.bend as SchemaJson
import ./responses-stream-content.bend as Content
import ./responses-messages.bend as Fixture
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/test/schema.bend as A

def contents(values: List<&2, T.AssistantContent<V.Value>>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case head <> tail: Content.block(head) <> contents(tail)

def reason(value: T.StopReason) -> String:
  match value:
    case T.Pending{}: "pending"
    case T.Stop{}: "stop"
    case T.Length{}: "length"
    case T.ToolUse{}: "toolUse"
    case T.Error{}: "error"
    case T.Aborted{}: "aborted"
    case T.Deferred{}: "deferred"

def snapshot(message: T.AssistantMessage<V.Value, Unit>) -> V.Value:
  match message:
    case T.AssistantMessage{blocks, _, _, _, _, _, _, _, _, stop, _, _, _, _, _}: V.ObjectValue{R.Record{R.Property{"content", V.ArrayValue{contents(blocks)}} <> R.Property{"stopReason", V.Text{reason(stop)}} <> Nil{}}}

def eventFields(kind: String, index: V.Value, extra: List<&2, R.Property<V.Value>>, message: T.AssistantMessage<V.Value, Unit>) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{kind}} <> R.Property{"contentIndex", index} <> List.append(&2, R.Property<V.Value>, extra, R.Property{"partial", snapshot(message)} <> Nil{})}}

def event(value: T.AssistantMessageEvent<V.Value, Unit>) -> V.Value:
  match value:
    case T.TextStart{index, partial}: eventFields("text_start", V.Number{index}, Nil{}, partial)
    case T.ThinkingStart{index, partial}: eventFields("thinking_start", V.Number{index}, Nil{}, partial)
    case T.ToolcallStart{index, partial}: eventFields("toolcall_start", V.Number{index}, Nil{}, partial)
    case T.TextDelta{index, delta, partial}: eventFields("text_delta", V.Number{index}, R.Property{"delta", V.Text{delta}} <> Nil{}, partial)
    case T.ThinkingDelta{index, delta, partial}: eventFields("thinking_delta", V.Number{index}, R.Property{"delta", V.Text{delta}} <> Nil{}, partial)
    case T.ToolcallDelta{index, delta, partial}: eventFields("toolcall_delta", V.Number{index}, R.Property{"delta", V.Text{delta}} <> Nil{}, partial)
    case T.TextEnd{index, text, partial}: eventFields("text_end", V.Number{index}, R.Property{"content", V.Text{text}} <> Nil{}, partial)
    case T.ThinkingEnd{index, text, partial}: eventFields("thinking_end", V.Number{index}, R.Property{"content", V.Text{text}} <> Nil{}, partial)
    case T.ToolcallEnd{index, tool, partial}: eventFields("toolcall_end", V.Number{index}, R.Property{"toolCall", Content.block(T.AssistantToolCall{tool})} <> Nil{}, partial)
    case _: V.Null{}

def events(values: List<&2, T.AssistantMessageEvent<V.Value, Unit>>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case head <> tail: event(head) <> events(tail)

def withError(fields: R.Record<V.Value>, error: Maybe<&2, Sampling.Error>) -> V.Value:
  match error:
    case None{}: V.ObjectValue{fields}
    case Some{value}: V.ObjectValue{R.set(V.Value, fields, "error", V.Text{Sampling.errorMessage(value)})}

def result(update: S.Update<Unit>) -> V.Value:
  match update:
    case S.Update{state, emitted, error}: withError(R.Record{R.Property{"output", snapshot(S.stateOutput(Unit, state))} <> R.Property{"events", V.ArrayValue{events(emitted)}} <> Nil{}}, error)


def run(inputs: List<&2, S.ContentEvent>, current: S.Update<Unit>) -> V.Value:
  match inputs current:
    case _ S.Update{state, emitted, Some{error}}: result(S.Update{state, emitted, Some{error}})
    case Nil{} update: result(update)
    case head <> tail S.Update{state, previous, None{}}: run(tail, S.prependEvents(Unit, previous, S.contentStep(Unit, state, head)))

def check(initial: List<&2, T.AssistantContent<V.Value>>, properties: R.Record<String>, inputs: List<&2, S.ContentEvent>, expected: String, label: String) -> IO(Unit):
  state = S.create(Unit, Fixture.assistantJson(initial, "openai-responses", "openai", "test", T.ToolUse{}), properties)
  actual = run(inputs, S.unchangedState(Unit, state))
  A.assertion(Content.encoded(Json.stringify(SchemaJson.toJson(actual)), expected), label)
