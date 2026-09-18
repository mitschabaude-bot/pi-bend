import Base
import ../src/types.bend as T
import ../src/tool-changes.bend as Changes
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/tool-declaration.bend as D
import ../../ai/src/utils/transcript.bend as Transcript
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/src/callback.bend as C
import ./message-events.bend as Test

def Message() -> Data: T.AgentMessage<V.Value, String, Unit, String, String>
def Messages() -> Data: List<&2, Message()>
def Input() -> Data: T.ToolExecutionInput<U32, Unit, String>
def Output() -> Data: Result<&2, &2, String, T.AgentToolResult<String>>
def Tool() -> Data: T.AgentTool<V.Value, U32, String, String, Unit, String>

def forbidden(unused: Unit, input: Input()) -> IO(Output()):
  IO.die(Output(), 1, "tool declaration must not execute tools")

def tools(values: List<&2, Ai.Tool<V.Value>>, +executor: C.Callback<Input(), Output()>) -> List<&2, Tool()>:
  match values:
    case Nil{}: Nil{}
    case Ai.Tool{name, description, schema, sampling} <> rest:
      T.AgentTool{name, description, schema, sampling, "display only", None{}, executor, None{}, Some{T.Sequential{}}} <> tools(rest, executor)

def declared(equal: D.DeclarationResult<Bool>) -> Bool:
  match equal:
    case D.Success{value}: value
    case D.Failure{_}: False{}

def sameTools(left: List<&2, Ai.Tool<V.Value>>, right: List<&2, Ai.Tool<V.Value>>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> xs b <> ys: declared(D.declarationsEqual(a, b)) && sameTools(xs, ys)
    case _ _: False{}

def maybeTools(left: Maybe<&2, List<&2, Ai.Tool<V.Value>>>, right: Maybe<&2, List<&2, Ai.Tool<V.Value>>>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: sameTools(a, b)
    case _ _: False{}

def sameReferences(left: List<&2, Ai.ToolReference>, right: List<&2, Ai.ToolReference>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Ai.ToolReference{a} <> xs Ai.ToolReference{b} <> ys: String.eq(a, b) && sameReferences(xs, ys)
    case _ _: False{}

def maybeReferences(left: Maybe<&2, List<&2, Ai.ToolReference>>, right: Maybe<&2, List<&2, Ai.ToolReference>>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: sameReferences(a, b)
    case _ _: False{}

def maybeText(left: Maybe<&2, String>, right: Maybe<&2, String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a, b)
    case _ _: False{}

def textBlocks(left: List<&2, Ai.TextContent>, right: List<&2, Ai.TextContent>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Ai.TextContent{a, sa} <> xs Ai.TextContent{b, sb} <> ys: String.eq(a, b) && maybeText(sa, sb) && textBlocks(xs, ys)
    case _ _: False{}

def content(left: Ai.SystemContent, right: Ai.SystemContent) -> Bool:
  match left right:
    case Ai.SystemText{a} Ai.SystemText{b}: String.eq(a, b)
    case Ai.SystemBlocks{a} Ai.SystemBlocks{b}: textBlocks(a, b)
    case _ _: False{}

def properties(left: List<&2, R.Property<Maybe<&2, String>>>, right: List<&2, R.Property<Maybe<&2, String>>>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case R.Property{a, va} <> xs R.Property{b, vb} <> ys: String.eq(a, b) && maybeText(va, vb) && properties(xs, ys)
    case _ _: False{}

def sections(left: Maybe<&2, R.Record<Maybe<&2, String>>>, right: Maybe<&2, R.Record<Maybe<&2, String>>>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{R.Record{a}} Some{R.Record{b}}: properties(a, b)
    case _ _: False{}

def system(left: Ai.SystemMessage<V.Value>, right: Ai.SystemMessage<V.Value>) -> Bool:
  match left right:
    case Ai.SystemMessage{a, sa, aa, ra, ta} Ai.SystemMessage{b, sb, ab, rb, tb}:
      content(a, b) && sections(sa, sb) && maybeTools(aa, ab) && maybeReferences(ra, rb) && V.equal(V.Number{ta}, V.Number{tb})

def same(left: Messages(), right: Messages()) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case T.CustomMessage{a} <> xs T.CustomMessage{b} <> ys: String.eq(a, b) && same(xs, ys)
    case T.LlmMessage{Ai.System{a}} <> xs T.LlmMessage{Ai.System{b}} <> ys: system(a, b) && same(xs, ys)
    case _ _: False{}

def checked(actual: D.DeclarationResult<Messages()>, expected: Messages(), label: String) -> IO(Unit):
  match actual:
    case D.Success{values}: Test.assertion(same(values, expected), label)
    case D.Failure{_}: Test.assertion(False{}, "unexpected declaration error")

def check(previous: Messages(), +pending: Messages(), available: List<&2, Ai.Tool<V.Value>>, expected: Messages(), timestampNeeded: Bool, label: String) -> IO(Unit):
  do IO<Unit>:
    +executor : C.Callback<Input(), Output()> <- C.create(~Unit, ~Input(), ~Output(), ~forbidden, Unit{})
    context : T.AgentContext<V.Value, String, Unit, String, String, U32, Unit, String> = T.AgentContext{previous, Some{tools(available, executor)}}
    +plan : D.DeclarationResult<Changes.ChangePlan<String, Unit, String, String>> = Changes.plan(String, Unit, String, String, U32, Unit, String, context, pending)
    Test.assertion(Bool.not(Bool.xor(Changes.needsTimestamp(String, Unit, String, String, plan), timestampNeeded)), "timestamp is requested only for a new declaration message")
    checked(Changes.applyAt(String, Unit, String, String, F.fromU32(777), plan), expected, label)
    C.dispose(Input(), Output(), executor)
