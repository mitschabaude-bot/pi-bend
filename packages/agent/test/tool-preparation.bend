import Base
import ../src/agent-loop.bend as Loop
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as C
import ./message-events.bend as Test
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/f64.bend as F

def Outcome() -> Data: Result<&2, &2, String, Loop.PreparedToolCallArguments>

def prepare(fail: Bool, raw: Schema.Value) -> IO(Result<&2, &2, String, Schema.Value>):
  do IO<Result<&2, &2, String, Schema.Value>>:
    Test.assertion(Schema.equal(raw, Schema.Text{"raw"}), "argument adapter must receive original arguments")
    return Bool.pick(Result<&2, &2, String, Schema.Value>, fail, Fail{"adapter failed"}, Done{Schema.Number{F.fromU32(42)}})

def check(outcome: Outcome(), mode: U32) -> IO(Unit):
  match outcome mode:
    case Done{Loop.OriginalCall{Ai.ToolCall{id, name, args, Some{signature}, Some{namespace}}}} 0:
      Test.assertion(String.eq(id, "id") && String.eq(name, "tool") && Schema.equal(args, Schema.Text{"raw"}) && String.eq(signature, "signature") && String.eq(namespace, "namespace"), "absent adapter must preserve call fields")
    case Done{Loop.ReplacedCall{Ai.ToolCall{id, name, args, Some{signature}, Some{namespace}}}} 1:
      Test.assertion(String.eq(id, "id") && String.eq(name, "tool") && Schema.equal(args, Schema.Number{F.fromU32(42)}) && String.eq(signature, "signature") && String.eq(namespace, "namespace"), "adapter must replace arguments and preserve call metadata")
    case Fail{error} 2: Test.assertion(String.eq(error, "adapter failed"), "adapter failure must propagate")
    case _ _: Test.assertion(False{}, "unexpected preparation outcome")

def main() -> IO(Unit):
  do IO<Unit>:
    +call : Ai.ToolCall<Schema.Value> = Ai.ToolCall{"id", "tool", Schema.Text{"raw"}, Some{"signature"}, Some{"namespace"}}
    absent : Outcome() <- Loop.prepareArgumentsWith(String, None{}, call)
    check(absent, 0)
    +adapter : C.Callback<Schema.Value, Result<&2, &2, String, Schema.Value>> <- C.create(~Bool, ~Schema.Value, ~Result<&2, &2, String, Schema.Value>, ~prepare, False{})
    result : Outcome() <- Loop.prepareArgumentsWith(String, Some{adapter}, call)
    check(result, 1)
    +failure : C.Callback<Schema.Value, Result<&2, &2, String, Schema.Value>> <- C.create(~Bool, ~Schema.Value, ~Result<&2, &2, String, Schema.Value>, ~prepare, True{})
    failed : Outcome() <- Loop.prepareArgumentsWith(String, Some{failure}, call)
    check(failed, 2)
    C.dispose(Schema.Value, Result<&2, &2, String, Schema.Value>, adapter)
    C.dispose(Schema.Value, Result<&2, &2, String, Schema.Value>, failure)
    IO.print("PASS typed argument preparation, metadata preservation and failure propagation")
