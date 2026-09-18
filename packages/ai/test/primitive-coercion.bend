import Base
import ../src/utils/validation.bend as Validation
import ../../runtime/src/schema-value.bend as V

def checked(result: Validation.Coercion(), expected: V.Value, label: String) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "number formatting failed")
    case Done{actual}: Bool.pick(IO(Unit), V.equal(actual, expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, label))

def check(value: V.Value, kind: String, expected: V.Value, label: String) -> IO(Unit):
  checked(Validation.coercePrimitiveByType(value, kind), expected, label)

def checkTypes(value: V.Value, types: List<&2, String>, expected: V.Value, label: String) -> IO(Unit):
  checked(Validation.coerceSchemaTypes(value, types), expected, label)
