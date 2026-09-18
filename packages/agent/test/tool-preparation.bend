import Base
import ../src/agent-loop.bend as Loop
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as C
import ./message-events.bend as Test

def Outcome() -> Data: Result<&2, &2, String, Loop.PreparedToolCallArguments<String, U32>>

def prepare(fail: Bool, raw: String) -> IO(Result<&2, &2, String, U32>):
  do IO<Result<&2, &2, String, U32>>:
    Test.assertion(String.eq(raw, "raw"), "argument adapter must receive original arguments")
    return Bool.pick(Result<&2, &2, String, U32>, fail, Fail{"adapter failed"}, Done{42})

def check(outcome: Outcome(), mode: U32) -> IO(Unit):
  match outcome mode:
    case Done{Loop.OriginalCall{Ai.ToolCall{id, name, args, Some{signature}, Some{namespace}}}} 0:
      Test.assertion(String.eq(id, "id") && String.eq(name, "tool") && String.eq(args, "raw") && String.eq(signature, "signature") && String.eq(namespace, "namespace"), "absent adapter must preserve call fields")
    case Done{Loop.ReplacedCall{Ai.ToolCall{id, name, args, Some{signature}, Some{namespace}}}} 1:
      Test.assertion(String.eq(id, "id") && String.eq(name, "tool") && U32.is_eq(args, 42) && String.eq(signature, "signature") && String.eq(namespace, "namespace"), "adapter must replace arguments and preserve call metadata")
    case Fail{error} 2: Test.assertion(String.eq(error, "adapter failed"), "adapter failure must propagate")
    case _ _: Test.assertion(False{}, "unexpected preparation outcome")

def main() -> IO(Unit):
  do IO<Unit>:
    +call : Ai.ToolCall<String> = Ai.ToolCall{"id", "tool", "raw", Some{"signature"}, Some{"namespace"}}
    absent : Outcome() <- Loop.prepareArgumentsWith(String, U32, String, None{}, call)
    check(absent, 0)
    +adapter : C.Callback<String, Result<&2, &2, String, U32>> <- C.create(~Bool, ~String, ~Result<&2, &2, String, U32>, ~prepare, False{})
    result : Outcome() <- Loop.prepareArgumentsWith(String, U32, String, Some{adapter}, call)
    check(result, 1)
    +failure : C.Callback<String, Result<&2, &2, String, U32>> <- C.create(~Bool, ~String, ~Result<&2, &2, String, U32>, ~prepare, True{})
    failed : Outcome() <- Loop.prepareArgumentsWith(String, U32, String, Some{failure}, call)
    check(failed, 2)
    C.dispose(String, Result<&2, &2, String, U32>, adapter)
    C.dispose(String, Result<&2, &2, String, U32>, failure)
    IO.print("PASS typed argument preparation, metadata preservation and failure propagation")
