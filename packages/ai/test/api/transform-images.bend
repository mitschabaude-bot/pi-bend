import Base
import ../../src/api/transform-messages.bend as Transform
import ../../src/types.bend as Ai
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/u64.bend as W
import ../../../runtime/test/schema.bend as T

def sameOptional(left: Maybe<&2, String>, right: Maybe<&2, String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a, b)
    case _ _: False{}

def sameContent(left: List<&2, Ai.TextImageContent>, right: List<&2, Ai.TextImageContent>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Ai.TextImageText{Ai.TextContent{a, sa}} <> left Ai.TextImageText{Ai.TextContent{b, sb}} <> right: String.eq(a, b) && sameOptional(sa, sb) && sameContent(left, right)
    case Ai.TextImageImage{Ai.ImageContent{a, ma}} <> left Ai.TextImageImage{Ai.ImageContent{b, mb}} <> right: String.eq(a, b) && String.eq(ma, mb) && sameContent(left, right)
    case _ _: False{}

def model(vision: Bool) -> Ai.Model<Unit>:
  +zero = F.fromU32(0)
  Ai.Model{"test", "Test", Ai.OpenAIResponsesApi{}, "test-provider", "https://example.test", True{}, None{}, Ai.InputText{} <> Bool.pick(List<&2, Ai.ModelInput>, vision, Ai.InputImage{} <> Nil{}, Nil{}), Ai.ModelCost{zero, zero, zero, zero, None{}}, F.fromU32(128000), F.fromU32(4096), None{}, None{}, None{}}

def checkMessages(messages: List<&2, Ai.Message<Unit, Unit, Unit, String>>, user: List<&2, Ai.TextImageContent>, tool: List<&2, Ai.TextImageContent>, label: String) -> IO(Unit):
  match messages:
    case Ai.User{Ai.UserMessage{Ai.UserBlocks{actualUser}, ut}} <> Ai.ToolResult{Ai.ToolResultMessage{"call", "tool", actualTool, Some{"details"}, None{}, True{}, tt}} <> Ai.User{Ai.UserMessage{Ai.UserText{"plain"}, pt}} <> Nil{}:
      T.assertion(sameContent(actualUser, user) && sameContent(actualTool, tool) && W.equal(F.toBits(ut), F.toBits(F.fromU32(41))) && W.equal(F.toBits(tt), F.toBits(F.fromU32(42))) && W.equal(F.toBits(pt), F.toBits(F.fromU32(43))), label)
    case _: T.assertion(False{}, "message structure/metadata changed: " ++ label)

def check(vision: Bool, +content: List<&2, Ai.TextImageContent>, user: List<&2, Ai.TextImageContent>, tool: List<&2, Ai.TextImageContent>, label: String) -> IO(Unit):
  messages = {Ai.User{Ai.UserMessage{Ai.UserBlocks{content}, F.fromU32(41)}} <> Ai.ToolResult{Ai.ToolResultMessage{"call", "tool", content, Some{"details"}, None{}, True{}, F.fromU32(42)}} <> Ai.User{Ai.UserMessage{Ai.UserText{"plain"}, F.fromU32(43)}} <> Nil{} : List<&2, Ai.Message<Unit, Unit, Unit, String>>}
  checkMessages(Transform.downgradeUnsupportedImages(Unit, Unit, Unit, String, Unit, messages, model(vision)), user, tool, label)
