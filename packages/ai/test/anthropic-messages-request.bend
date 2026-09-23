import Base
import ../src/api/anthropic-messages.bend as Anthropic
import ../src/providers/anthropic.models.bend as Catalog
import ../src/types.bend as T
import ../src/utils/json.bend as Wire
import ../../runtime/src/f64.bend as F
import ../../runtime/src/json.bend as Json
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V

# Fixtures follow pi-mono f07218c4d anthopic eager-tool, thinking and SSE
# tests. Compare decoded wire values so property insertion order is immaterial.
def schema() -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"value", V.ObjectValue{R.Record{R.Property{"type", V.Text{"string"}} <> Nil{}}}} <> Nil{}}}} <> R.Property{"required", V.ArrayValue{V.Text{"value"} <> Nil{}}} <> Nil{}}}

def initial() -> T.SystemMessage<V.Value>:
  T.SystemMessage{T.SystemText{"You are helpful."}, None{}, Some{T.Tool{"lookup", "Look up a value", schema(), None{}} <> Nil{}}, None{}, F.fromU32(1)}

def basic() -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  T.TranscriptContext{T.System{initial()} <> T.User{T.UserMessage{T.UserText{"Use the tool"}, F.fromU32(2)}} <> Nil{}}

def replay() -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  +zero = F.fromU32(0)
  +usage = {T.Usage{zero, zero, zero, zero, None{}, None{}, zero, T.UsageCost{zero, zero, zero, zero, zero}} : T.Usage}
  +thinking = {T.AssistantThinking{T.ThinkingContent{"reasoning", Some{"signature"}, None{}}} : T.AssistantContent<V.Value>}
  +call = {T.AssistantToolCall{T.ToolCall{"toolu_1", "lookup", V.ObjectValue{R.Record{R.Property{"value", V.Text{"42"}} <> Nil{}}}, None{}, None{}}} : T.AssistantContent<V.Value>}
  T.TranscriptContext{T.System{initial()} <> T.User{T.UserMessage{T.UserText{"Use the tool"}, F.fromU32(2)}} <> T.Assistant{T.AssistantMessage{thinking <> call <> Nil{}, "anthropic-messages", "anthropic", "claude-opus-5", None{}, None{}, None{}, None{}, usage, T.ToolUse{}, None{}, None{}, None{}, None{}, F.fromU32(3)}} <> T.ToolResult{T.ToolResultMessage{"toolu_1", "lookup", T.TextImageText{T.TextContent{"found", None{}}} <> Nil{}, None{}, None{}, False{}, F.fromU32(4)}} <> Nil{}}

def options(mode: String) -> Anthropic.Options:
  match mode:
    case "adaptive": Anthropic.Options{None{}, Some{F.fromU32(1)}, Anthropic.AdaptiveThinking{Some{"high"}, "summarized"}, Some{Anthropic.Auto{}}, T.CacheNone{}, False{}}
    case "replay": Anthropic.Options{None{}, None{}, Anthropic.NoThinking{}, None{}, T.CacheNone{}, False{}}
    case "cache": Anthropic.Options{None{}, None{}, Anthropic.NoThinking{}, None{}, T.CacheShort{}, False{}}
    case _: Anthropic.Options{None{}, None{}, Anthropic.NoThinking{}, None{}, T.CacheNone{}, False{}}

def context(mode: String) -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  match mode:
    case "replay": replay()
    case _: basic()

def output(wire: String, result: Result<&2, &2, Json.ParseError, V.Value>, expected: Result<&2, &2, Json.ParseError, V.Value>) -> IO(Unit):
  match result expected:
    case Done{actual} Done{wanted}: Bool.pick(IO(Unit), V.equal(actual, wanted), IO.print("PASS Anthropic request"), IO.die(Unit, 1, "Anthropic request mismatch: " ++ wire))
    case _ _: IO.die(Unit, 1, "invalid fixture")

def runEncoded(wanted: String, encoded: Maybe<&2, String>) -> IO(Unit):
  match encoded:
    case None{}: IO.die(Unit, 1, "invalid payload")
    case Some{+wire}: output(wire, Json.parse(wire), Json.parse(wanted))

def run(+mode: String, wanted: String) -> IO(Unit):
  runEncoded(wanted, Wire.stringify(Anthropic.buildParams(Unit, Unit, Catalog.model_claude_opus_5(), context(mode), options(mode))))

def args(values: List<String>) -> IO(Unit):
  match values:
    case mode <> expected <> Nil{}: run(mode, expected)
    case _: IO.die(Unit, 1, "expected mode and JSON")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
