import Base
import ../src/utils/validation.bend as V
import ../../runtime/src/schema-value.bend as S
import ../../runtime/src/record.bend as R

def assertion(ok: Bool, label: String) -> IO(Unit):
  Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.die(Unit, 1, label))

def check(value: S.Value, kind: String, +expected: Bool) -> IO(Unit):
  +actual = V.matchesJsonType(value, kind)
  assertion((actual && expected) || (Bool.not(actual) && Bool.not(expected)), "validation type predicate differs")

def equalStrings(a: List<&2, String>, b: List<&2, String>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: String.eq(x, y) && equalStrings(xs, ys)
    case _ _: False{}

def checkTypes(value: S.Value, expected: List<&2, String>) -> IO(Unit):
  schema = R.set(S.Value, R.new(S.Value), "type", value)
  assertion(equalStrings(V.getSchemaTypes(schema), expected), "schema type filtering differs")

def missingType() -> IO(Unit):
  assertion(equalStrings(V.getSchemaTypes(R.new(S.Value)), Nil{}), "absent schema type must return an empty list")
