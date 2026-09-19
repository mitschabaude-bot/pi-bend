import Base
import ../src/utils/json-parse.bend as Json
import ../../runtime/src/json-parse.bend as Strict
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/utf16.bend as U
import ../../runtime/test/schema.bend as Assert

def parsed(actual: Result<&2,&2,Strict.Error,V.Value>, expected: Maybe<&2,V.Value>) -> Bool:
  match actual expected:
    case Fail{_} None{}: True{}
    case Done{value} Some{wanted}: V.equal(value,wanted)
    case _ _: False{}

def check(+input: String, repaired: String, expected: Maybe<&2,V.Value>, +label: String) -> IO(Unit):
  do IO<Unit>:
    Assert.assertion(U.equal(Json.repairJson(input),repaired),"repaired spelling: " ++ label)
    Assert.assertion(parsed(Json.parseJsonWithRepair(input),expected),"repair parse result: " ++ label)
