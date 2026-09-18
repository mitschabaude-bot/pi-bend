import Base
import ../src/utils/validation.bend as V
import ../../runtime/src/schema-value.bend as S
import ../../runtime/src/record.bend as R

def assertion(ok: Bool, label: String) -> IO(Unit):
  Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.die(Unit, 1, label))

def check(value: S.Value<U32>, kind: String, +expected: Bool) -> IO(Unit):
  +actual = V.matchesJsonType(U32, value, kind)
  assertion((actual && expected) || (Bool.not(actual) && Bool.not(expected)), "validation type predicate differs")

def equalStrings(a: List<&2, String>, b: List<&2, String>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: String.eq(x, y) && equalStrings(xs, ys)
    case _ _: False{}

def checkTypes(value: S.Value<U32>, enumerable: Bool, expected: List<&2, String>) -> IO(Unit):
  schema = R.set(S.Property<S.Value<U32>>, R.new(S.Property<S.Value<U32>>), "type", S.Property{value, enumerable})
  assertion(equalStrings(V.getSchemaTypes(U32, schema), expected), "schema type filtering differs")

def missingType() -> IO(Unit):
  assertion(equalStrings(V.getSchemaTypes(U32, R.new(S.Property<S.Value<U32>>)), Nil{}), "absent schema type must return an empty list")
