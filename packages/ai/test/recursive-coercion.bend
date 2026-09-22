import Base
import ../src/utils/validation.bend as Validation
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/schema.bend as L
import ../../runtime/src/record.bend as R
import ../../runtime/test/schema.bend as T

def outcome(result: Validation.Coercion(), expected: V.Value, label: String) -> IO(Unit):
  match result:
    case Done{actual}: T.assertion(V.equal(actual, expected), label)
    case Fail{_}: T.assertion(False{}, "unexpected recursive coercion error: " ++ label)

def check(+input: V.Value, schema: V.Value, expected: V.Value, original: V.Value, label: String) -> IO(Unit):
  do IO<Unit>:
    outcome(Validation.coerceWithJsonSchema(input, schema), expected, label)
    T.assertion(V.equal(input, original), "recursive coercion must preserve caller input")

def pending(result: Validation.Coercion()) -> IO(Unit):
  match result:
    case Fail{Validation.PendingBooleanUnion{}}: IO.pure(Unit, Unit{})
    case _: T.assertion(False{}, "true union-arm cache behavior remains pending")

def unsupported(result: Validation.Coercion()) -> IO(Unit):
  match result:
    case Fail{Validation.UnionSchemaFailure{L.LoadError{_, L.UnsupportedKeyword{keyword}}}}: T.assertion(String.eq(keyword, "pattern"), "unsupported union constraint")
    case _: T.assertion(False{}, "unsupported union checks must remain explicit")

def main() -> IO(Unit):
  do IO<Unit>:
    +input : V.Value = V.Text{"42"}
    schema : V.Value = V.ObjectValue{R.Record{R.Property{"anyOf", V.ArrayValue{V.ObjectValue{R.Record{R.Property{"pattern", V.Text{"x"}} <> Nil{}}} <> Nil{}}} <> Nil{}}}
    unsupported(Validation.coerceWithJsonSchema(input, schema))
    T.assertion(V.equal(input, V.Text{"42"}), "unsupported union must preserve original input")
    IO.print("PASS explicit unsupported union checks and immutable input")
