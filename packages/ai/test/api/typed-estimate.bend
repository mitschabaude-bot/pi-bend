import Base
import ../../src/types.bend as T
import ../../src/utils/estimate.bend as E
import ../../src/api/simple-options.bend as O
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F
import ../../../runtime/test/schema.bend as Assert
import ../context-estimate.bend as Named
import ./context-estimate.bend as Check

type Parameters is Data:
  Parameters{kind: String}

type Arguments is Data:
  Arguments{payload: String}

def encodeParameters(value: Parameters) -> T.JsonValue:
  match value:
    case Parameters{kind}: T.JsonObject{R.Record{R.Property{"type", T.JsonString{kind}} <> Nil{}}}

def encodeArguments(value: Arguments) -> T.JsonValue:
  match value:
    case Arguments{payload}: T.JsonObject{R.Record{R.Property{"payload", T.JsonString{payload}} <> Nil{}}}

def messages() -> List<&2, T.Message<Parameters, Arguments, Unit, Unit>>:
  +zero = F.fromU32(0)
  system = {T.System{T.SystemMessage{T.SystemText{""}, None{}, Some{T.Tool{"calc", "", Parameters{"integer"}, None{}} <> Nil{}}, None{}, zero}} : T.Message<Parameters, Arguments, Unit, Unit>}
  assistant = {T.Assistant{T.AssistantMessage{T.AssistantToolCall{T.ToolCall{"id", "fn", Arguments{"hello"}, None{}, None{}}} <> Nil{}, "openai-responses", "openai", "test", None{}, None{}, None{}, None{}, Named.usage(zero), T.ToolUse{}, None{}, None{}, None{}, None{}, zero}} : T.Message<Parameters, Arguments, Unit, Unit>}
  system <> assistant <> Nil{}

def maxTokens(options: T.StreamOptions<Unit, Unit, Unit, Unit, String>) -> Bool:
  match options:
    case T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, Some{value}, _, _, _, _, _}: E.equalOrder(F.compare(value, F.fromU32(5881)))
    case _: False{}

def main() -> IO(Unit):
  +context = {T.TranscriptContext{messages()} : T.TranscriptContext<Parameters, Arguments, Unit, Unit>}
  do IO<Unit>:
    Assert.assertion(Check.same(E.estimateContextTokensWith(~Parameters, ~Arguments, ~Unit, ~Unit, ~encodeParameters, ~encodeArguments, context), E.ContextUsageEstimate{F.fromU32(23), F.fromU32(0), F.fromU32(23), None{}}), "typed schema and arguments context estimate")
    Assert.assertion(maxTokens(O.buildBaseOptionsWith(~Parameters, ~Arguments, ~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~String, ~encodeParameters, ~encodeArguments, Named.model(), context, None{}, None{})), "typed estimate reaches provider options")
    IO.print("PASS application-specific schema/argument records reach estimation and provider options")
