import Base
import ./tool-changes.bend as Test
import ./message-events.bend as Assert
import ../src/tool-changes.bend as Changes
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/tool-declaration.bend as D
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/src/callback.bend as C

def created(actual: D.DeclarationResult<Test.Messages()>, expected: Ai.Tool<V.Value>) -> IO(Unit):
  match actual:
    case D.Success{T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{text}, None{}, Some{tool <> Nil{}}, None{}, timestamp}}} <> T.CustomMessage{pending} <> Nil{}}:
      Assert.assertion(String.is_empty(text) && String.eq(pending, "pending") && Test.declared(D.declarationsEqual(tool, expected)) && Bool.not(V.equal(V.Number{timestamp}, V.Number{F.fromU32(0)})), "new tool delta uses a clock timestamp and precedes pending content")
    case _: Assert.assertion(False{}, "unexpected clocked declaration")

def main() -> IO(Unit):
  do IO<Unit>:
    +executor : C.Callback<Test.Input(), Test.Output()> <- C.create(~Unit, ~Test.Input(), ~Test.Output(), ~Test.forbidden, Unit{})
    +tool : Ai.Tool<V.Value> = Ai.Tool{"echo", "Echo", V.Null{}, None{}}
    +context : T.AgentContext<V.Value, String, Unit, String, String, U32, Unit, String> = T.AgentContext{Nil{}, Some{Test.tools(tool <> Nil{}, executor)}}
    newMessage : D.DeclarationResult<Test.Messages()> <- Changes.declareToolChanges(String, Unit, String, String, U32, Unit, String, context, T.CustomMessage{"pending"} <> Nil{})
    created(newMessage, tool)
    preserved : D.DeclarationResult<Test.Messages()> <- Changes.declareToolChanges(String, Unit, String, String, U32, Unit, String, context, T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{"keep"}, None{}, None{}, None{}, F.fromU32(12)}}} <> Nil{})
    Test.checked(preserved, T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{"keep"}, None{}, Some{tool <> Nil{}}, None{}, F.fromU32(12)}}} <> Nil{}, "existing system content and timestamp survive IO declaration")
    empty : D.DeclarationResult<Test.Messages()> <- Changes.declareToolChanges(String, Unit, String, String, U32, Unit, String, T.AgentContext{Nil{}, None{}}, Nil{})
    Test.checked(empty, Nil{}, "absent tool loadout produces no empty declaration")
    left : V.Value = V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"additionalProperties", V.Boolean{True{}}} <> Nil{}}}
    right : V.Value = V.ObjectValue{R.Record{R.Property{"additionalProperties", V.Boolean{True{}}} <> R.Property{"type", V.Text{"object"}} <> Nil{}}}
    previous : Test.Messages() = T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{""}, None{}, Some{Ai.Tool{"echo", "Echo", left, None{}} <> Nil{}}, None{}, F.fromU32(12)}}} <> Nil{}
    Test.check(previous, T.CustomMessage{"pending"} <> Nil{}, Ai.Tool{"echo", "Echo", right, None{}} <> Nil{}, T.CustomMessage{"pending"} <> Nil{}, False{}, "approved schema field-order equality does not declare a redefinition")
    C.dispose(Test.Input(), Test.Output(), executor)
    IO.print("PASS native declaration clock boundary, existing timestamp preservation, absent tool loadout and structural schema equality")
