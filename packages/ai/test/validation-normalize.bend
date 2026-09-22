import Base
import ../src/utils/validation.bend as Validation
import ../src/utils/validation-normalize.bend as N
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/schema.bend as L
import ../../runtime/src/record.bend as R
import ../../runtime/test/schema.bend as T

def normalized(result: N.Outcome(), expected: V.Value, label: String) -> IO(Unit):
  match result:
    case Done{actual}: T.assertion(V.equal(actual, expected), label)
    case Fail{_}: T.assertion(False{}, "unexpected normalization error: " ++ label)

def check(+input: V.Value, schema: V.Value, expected: V.Value, original: V.Value, label: String) -> IO(Unit):
  do IO<Unit>:
    normalized(Validation.normalizeOptionalNulls(input, schema), expected, label)
    T.assertion(V.equal(input, original), "normalization must preserve the caller input")

def unsupported(result: N.Outcome()) -> IO(Unit):
  match result:
    case Fail{N.Error{path, L.LoadError{schemaPath, L.UnsupportedKeyword{keyword}}}}:
      T.assertion(String.eq(String.join(path, "/"), "x") && String.eq(String.join(schemaPath, "/"), "pattern") && String.eq(keyword, "pattern"), "normalization must expose unsupported nullability decision")
    case _: T.assertion(False{}, "unsupported nullability cannot silently pass")

def pending(result: N.Outcome()) -> IO(Unit):
  match result:
    case Fail{N.PendingBooleanNull{path}}: T.assertion(String.eq(String.join(path, "/"), "x"), "pending boolean-schema decision path")
    case _: T.assertion(False{}, "boolean false normalization decision must remain explicit")

def main() -> IO(Unit):
  do IO<Unit>:
    +input : V.Value = V.ObjectValue{R.Record{R.Property{"x", V.Null{}} <> Nil{}}}
    schema : V.Value = V.ObjectValue{R.Record{R.Property{"properties", V.ObjectValue{R.Record{R.Property{"x", V.ObjectValue{R.Record{R.Property{"pattern", V.Text{"x"}} <> Nil{}}}} <> Nil{}}}} <> Nil{}}}
    unsupported(Validation.normalizeOptionalNulls(input, schema))
    T.assertion(V.equal(input, V.ObjectValue{R.Record{R.Property{"x", V.Null{}} <> Nil{}}}), "failed normalization must leave input intact")
    IO.print("PASS unsupported nullability errors and retained input")
