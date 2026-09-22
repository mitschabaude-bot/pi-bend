import Base
import ../../src/api/openai-responses-stream.bend as C
import ../../src/api/constrained-sampling.bend as Sampling
import ../../src/types.bend as T
import ../../src/utils/json.bend as Json
import ../../src/utils/schema-json.bend as SchemaJson
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/utf16.bend as Utf16
import ../../../runtime/test/schema.bend as A

def optional(fields: R.Record<V.Value>, name: String, value: Maybe<&2, String>) -> R.Record<V.Value>:
  match value:
    case None{}: fields
    case Some{text}: R.set(V.Value, fields, name, V.Text{text})

def block(value: T.AssistantContent<V.Value>) -> V.Value:
  match value:
    case T.AssistantText{T.TextContent{text, signature}}: V.ObjectValue{optional(R.Record{R.Property{"type", V.Text{"text"}} <> R.Property{"text", V.Text{text}} <> Nil{}}, "textSignature", signature)}
    case T.AssistantThinking{T.ThinkingContent{text, signature, _}}: V.ObjectValue{optional(R.Record{R.Property{"type", V.Text{"thinking"}} <> R.Property{"thinking", V.Text{text}} <> Nil{}}, "thinkingSignature", signature)}
    case T.AssistantToolCall{T.ToolCall{id, name, arguments, _, namespace}}: V.ObjectValue{optional(R.Record{R.Property{"type", V.Text{"toolCall"}} <> R.Property{"id", V.Text{id}} <> R.Property{"name", V.Text{name}} <> R.Property{"arguments", arguments} <> Nil{}}, "namespace", namespace)}

def signal(kind: String, value: T.AssistantContent<V.Value>, delta: Maybe<&2, String>) -> V.Value:
  V.ObjectValue{optional(R.Record{R.Property{"kind", V.Text{kind}} <> R.Property{"content", block(value)} <> Nil{}}, "delta", delta)}

def signals(values: List<&2, C.Signal>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case C.Started{value} <> rest: signal("started", value, None{}) <> signals(rest)
    case C.Delta{value, delta} <> rest: signal("delta", value, Some{delta}) <> signals(rest)
    case C.Ended{value} <> rest: signal("ended", value, None{}) <> signals(rest)

def result(value: C.Block, emitted: List<&2, C.Signal>, error: Maybe<&2, String>) -> V.Value:
  V.ObjectValue{optional(R.Record{R.Property{"content", block(C.blockContent(value))} <> R.Property{"signals", V.ArrayValue{signals(emitted)}} <> Nil{}}, "error", error)}

def advance(old: C.Block, previous: List<&2, C.Signal>, next: Result<&2, &2, Sampling.Error, C.BlockUpdate>) -> Result<&2, &2, V.Value, C.BlockUpdate>:
  match next:
    case Fail{error}: Fail{result(old, previous, Some{Sampling.errorMessage(error)})}
    case Done{C.BlockUpdate{value, emitted, finished}}: Done{C.BlockUpdate{value, List.append(&2, C.Signal, previous, emitted), finished}}

def run(inputs: List<&2, C.Input>, current: Result<&2, &2, V.Value, C.BlockUpdate>) -> V.Value:
  match inputs current:
    case _ Fail{value}: value
    case Nil{} Done{C.BlockUpdate{value, emitted, _}}: result(value, emitted, None{})
    case _ Done{C.BlockUpdate{value, emitted, True{}}}: result(value, emitted, None{})
    case head <> tail Done{C.BlockUpdate{+value, +emitted, _}}: run(tail, advance(value, emitted, C.blockStep(value, head)))

def started(inputs: List<&2, C.Input>, value: Maybe<&2, C.BlockUpdate>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{update}: run(inputs, Done{update})

def encoded(value: Maybe<&2, String>, expected: String) -> Bool:
  match value:
    case None{}: False{}
    case Some{text}: Utf16.equal(text, expected)

def check(item: C.OutputItem, properties: R.Record<String>, inputs: List<&2, C.Input>, expected: String, label: String) -> IO(Unit):
  A.assertion(encoded(Json.stringify(SchemaJson.toJson(started(inputs, C.startBlock(item, properties)))), expected), label)
