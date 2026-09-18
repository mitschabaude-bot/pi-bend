import Base
import ../src/types.bend as T
import ../src/utils/transcript.bend as Transcript
import ../src/utils/tool-declaration.bend as D
import ../../agent/src/types.bend as A
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/schema-value.bend as S
import ./tool-state.bend as Fixture
import ./tool-declaration.bend as H

def ExecuteInput() -> Data: A.ToolExecutionInput<Unit, Unit, Unit>
def ExecuteResult() -> Data: Result<&2, &2, String, A.AgentToolResult<Unit>>
def PrepareResult() -> Data: Result<&2, &2, String, Unit>
def ExecutableTool() -> Data: A.AgentTool<S.Value, Unit, Unit, Unit, Unit, String>

def executeBody(counter: Ref.Ref<U32>) -> ExecuteInput() -> IO(ExecuteResult()):
  input => do IO<ExecuteResult()>:
    ignored : Unit <- Ref.modify(U32, Unit, counter, n => ((n + 1 : U32), Unit{}))
    return Done{A.AgentToolResult{Nil{}, Unit{}, None{}, None{}}}

def prepareBody(counter: Ref.Ref<U32>) -> Unit -> IO(PrepareResult()):
  input => do IO<PrepareResult()>:
    ignored : Unit <- Ref.modify(U32, Unit, counter, n => ((n + 1 : U32), Unit{}))
    return Done{Unit{}}

def view(tool: ExecutableTool()) -> T.Tool<S.Value>:
  A.toTool(S.Value, Unit, Unit, Unit, Unit, String, tool)

# Original three assertions from system-message-replay.test.ts. The executable
# is a real typed AgentTool; Bend makes its structural base view explicit.
def upstreamCase() -> IO(Unit):
  do IO<Unit>:
    +counter : Ref.Ref<U32> <- Ref.new(U32, 0)
    +execute : C.Callback<ExecuteInput(), ExecuteResult()> <- C.create(~Ref.Ref<U32>, ~ExecuteInput(), ~ExecuteResult(), ~executeBody, counter)
    +prepare : C.Callback<Unit, PrepareResult()> <- C.create(~Ref.Ref<U32>, ~Unit, ~PrepareResult(), ~prepareBody, counter)
    executable : ExecutableTool() = A.AgentTool{"a", "a tool", Fixture.emptyObjectSchema(), None{}, "display-only label", Some{prepare}, execute, Some{A.Safe{}}, Some{A.Parallel{}}}
    H.assertion(H.sameBool(Transcript.declarationsEqual(view(executable), Fixture.tool("a", "a tool")), D.Success{True{}}), "executable and undefined fields must not affect declaration equality")
    H.assertion(H.sameBool(Transcript.declarationsEqual(Fixture.tool("a", "a tool"), Fixture.tool("a", "changed")), D.Success{False{}}), "description changes must affect declaration equality")
    H.assertion(H.sameBool(Transcript.declarationsEqual(Fixture.tool("a", "a tool"), T.Tool{"a", "a tool", Fixture.emptyObjectSchema(), Some{T.SamplingDisabled{}}}), D.Success{False{}}), "absent sampling must differ from explicitly false")
    calls : U32 <- Ref.read(U32, counter)
    H.assertion(U32.is_eq(calls, 0), "declaration projection must not prepare or execute a tool")
    C.dispose(ExecuteInput(), ExecuteResult(), execute)
    C.dispose(Unit, PrepareResult(), prepare)
    previous : U32 <- Ref.dispose(U32, counter)
    IO.print("PASS compares tool declarations without executable or undefined fields")
