import Base
import ../src/api/google-generative-ai.bend as Google
import ../src/api/google-generative-ai-stream.bend as Stream
import ../src/api/constrained-sampling.bend as Constrained
import ../src/providers/google.models.bend as Models
import ../src/types.bend as T
import ../src/utils/json.bend as Wire
import ../../runtime/src/f64.bend as F
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R

def model() -> T.Model<T.JsonValue>: Models.model_gemini_2_5_flash()

def assistant() -> T.AssistantMessage<V.Value, Unit>:
  T.AssistantMessage{T.AssistantThinking{T.ThinkingContent{"reasoning", Some{"c2ln"}, None{}}} <> T.AssistantText{T.TextContent{"", Some{"c2ln"}}} <> Nil{}, "google-generative-ai", "google", "gemini-2.5-flash", None{}, None{}, None{}, None{}, Stream.emptyUsage(), T.Stop{}, None{}, None{}, None{}, None{}, F.fromU32(2)}

def context() -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  T.TranscriptContext{T.User{T.UserMessage{T.UserText{"ping"}, F.fromU32(1)}} <> T.Assistant{assistant()} <> Nil{}}

def gemini3() -> T.Model<T.JsonValue>: Models.model_gemini_3_flash_preview()

def propertySchema() -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{"string"}} <> Nil{}}}

def strictSchema() -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"optional", propertySchema()} <> R.Property{"required", propertySchema()} <> Nil{}}}} <> R.Property{"required", V.ArrayValue{V.Text{"required"} <> Nil{}}} <> Nil{}}}

def unsupportedSchema() -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"value", V.ObjectValue{R.Record{R.Property{"$ref", V.Text{"#/definitions/value"}} <> Nil{}}}} <> Nil{}}}} <> Nil{}}}

def strictTool(schema: V.Value, policy: T.SamplingStrictness) -> T.Tool<V.Value>:
  T.Tool{"lookup", "Look up a value", schema, Some{T.SamplingConfigured{T.JsonSchemaSampling{policy}}}}

def strictContext(schema: V.Value, policy: T.SamplingStrictness) -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  T.TranscriptContext{T.System{T.SystemMessage{T.SystemText{"Use lookup."}, None{}, Some{strictTool(schema, policy) <> Nil{}}, None{}, F.fromU32(1)}} <> T.User{T.UserMessage{T.UserText{"lookup 42"}, F.fromU32(2)}} <> Nil{}}

def imageAssistant(id: String) -> T.AssistantMessage<V.Value, Unit>:
  T.AssistantMessage{T.AssistantToolCall{T.ToolCall{"call-img", "lookup", V.ObjectValue{R.new(V.Value)}, None{}, None{}}} <> T.AssistantToolCall{T.ToolCall{"call-text", "lookup", V.ObjectValue{R.new(V.Value)}, None{}, None{}}} <> Nil{}, "google-generative-ai", "google", id, None{}, None{}, None{}, None{}, Stream.emptyUsage(), T.ToolUse{}, None{}, None{}, None{}, None{}, F.fromU32(2)}

def imageContext(id: String) -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  T.TranscriptContext{T.User{T.UserMessage{T.UserText{"ping"}, F.fromU32(1)}} <> T.Assistant{imageAssistant(id)} <> T.ToolResult{T.ToolResultMessage{"call-img", "lookup", T.TextImageImage{T.ImageContent{"aGVsbG8=", "image/png"}} <> Nil{}, None{}, None{}, False{}, F.fromU32(3)}} <> T.ToolResult{T.ToolResultMessage{"call-text", "lookup", T.TextImageText{T.TextContent{"found", None{}}} <> Nil{}, None{}, None{}, False{}, F.fromU32(4)}} <> Nil{}}

def updatedContext() -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  T.TranscriptContext{T.System{T.SystemMessage{T.SystemText{"Base rule."}, None{}, Some{T.Tool{"old", "Old tool", strictSchema(), None{}} <> Nil{}}, None{}, F.fromU32(1)}} <> T.User{T.UserMessage{T.UserText{"ping"}, F.fromU32(2)}} <> T.System{T.SystemMessage{T.SystemText{"Second rule."}, None{}, Some{T.Tool{"lookup", "Look up a value", strictSchema(), None{}} <> Nil{}}, Some{T.ToolReference{"old"} <> Nil{}}, F.fromU32(3)}} <> T.User{T.UserMessage{T.UserText{"after update"}, F.fromU32(4)}} <> Nil{}}

def display(result: Result<&2, &2, Constrained.Error, T.JsonValue>) -> IO(Unit):
  match result:
    case Done{value}: IO.print(Maybe.default(&2, String, Wire.stringify(value), ""))
    case Fail{error}: IO.print("error: " ++ Constrained.errorMessage(error))

def options() -> Google.Options: Google.Options{None{}, None{}, Google.NoThinking{}, None{}}

def run(mode: String) -> IO(Unit):
  match mode:
    case "strict": display(Google.buildParams(Unit, Unit, gemini3(), strictContext(strictSchema(), T.Require{}), options()))
    case "strict-prefer": display(Google.buildParams(Unit, Unit, gemini3(), strictContext(unsupportedSchema(), T.Prefer{}), options()))
    case "strict-unsupported": display(Google.buildParams(Unit, Unit, model(), strictContext(strictSchema(), T.Require{}), options()))
    case "legacy-image": display(Google.buildParams(Unit, Unit, model(), imageContext("gemini-2.5-flash"), options()))
    case "modern-image": display(Google.buildParams(Unit, Unit, gemini3(), imageContext("gemini-3-flash-preview"), options()))
    case "system-update": display(Google.buildParams(Unit, Unit, model(), updatedContext(), options()))
    case _: display(Google.buildParams(Unit, Unit, model(), context(), options()))

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> _: run(mode)
    case Nil{}: run("signed")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
