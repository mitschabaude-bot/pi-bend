import Base
import ../../src/api/transform-messages.bend as Transform
import ../../src/types.bend as Ai
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/u64.bend as W
import ../../../runtime/test/schema.bend as T
import ./transform-images.bend as Images

def sameBool(left: Maybe<&2, Bool>, right: Maybe<&2, Bool>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{+b}: Bool.pick(Bool, a, b, Bool.not(b))
    case _ _: False{}

def sameContent(left: List<&2, Ai.AssistantContent<String>>, right: List<&2, Ai.AssistantContent<String>>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Ai.AssistantText{Ai.TextContent{a, sa}} <> left Ai.AssistantText{Ai.TextContent{b, sb}} <> right:
      String.eq(a, b) && Images.sameOptional(sa, sb) && sameContent(left, right)
    case Ai.AssistantThinking{Ai.ThinkingContent{a, sa, ra}} <> left Ai.AssistantThinking{Ai.ThinkingContent{b, sb, rb}} <> right:
      String.eq(a, b) && Images.sameOptional(sa, sb) && sameBool(ra, rb) && sameContent(left, right)
    case Ai.AssistantToolCall{Ai.ToolCall{a, na, aa, sa, nsa}} <> left Ai.AssistantToolCall{Ai.ToolCall{b, nb, ab, sb, nsb}} <> right:
      String.eq(a, b) && String.eq(na, nb) && String.eq(aa, ab) && Images.sameOptional(sa, sb) && Images.sameOptional(nsa, nsb) && sameContent(left, right)
    case _ _: False{}

def source(content: List<&2, Ai.AssistantContent<String>>, api: String, provider: String, model: String) -> Ai.AssistantMessage<String, Unit>:
  +zero = F.fromU32(0)
  usage = {Ai.Usage{zero, zero, zero, zero, None{}, None{}, F.fromU32(42), Ai.UsageCost{zero, zero, zero, zero, zero}} : Ai.Usage}
  Ai.AssistantMessage{content, api, provider, model, Some{"response-model"}, Some{"response-id"}, Some{"high"}, None{}, usage, Ai.Stop{}, None{}, Some{"metadata"}, Some{"raw"}, Some{False{}}, F.fromU32(17)}

def checked(message: Ai.AssistantMessage<String, Unit>, expected: List<&2, Ai.AssistantContent<String>>, api: String, provider: String, model: String, label: String) -> IO(Unit):
  match message:
    case Ai.AssistantMessage{content, actualApi, actualProvider, actualModel, Some{"response-model"}, Some{"response-id"}, Some{"high"}, None{}, Ai.Usage{_, _, _, _, None{}, None{}, total, _}, Ai.Stop{}, None{}, Some{"metadata"}, Some{"raw"}, Some{False{}}, timestamp}:
      T.assertion(sameContent(content, expected) && String.eq(actualApi, api) && String.eq(actualProvider, provider) && String.eq(actualModel, model) && W.equal(F.toBits(total), F.toBits(F.fromU32(42))) && W.equal(F.toBits(timestamp), F.toBits(F.fromU32(17))), label)
    case _: T.assertion(False{}, "replay metadata changed: " ++ label)

def check(content: List<&2, Ai.AssistantContent<String>>, expected: List<&2, Ai.AssistantContent<String>>, +api: String, +provider: String, +model: String, label: String) -> IO(Unit):
  checked(Transform.replayAssistant(String, Unit, Unit, source(content, api, provider, model), Images.model(True{})), expected, api, provider, model, label)
