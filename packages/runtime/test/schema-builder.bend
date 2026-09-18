import Base
import ../../ai/src/utils/validation-normalize.bend as Normalize
import ../src/record.bend as R
import ../src/schema-errors.bend as E
import ../../ai/src/utils/validation-errors.bend as Errors
import ../src/f64.bend as F
import ../src/schema-builder.bend as D
import ../src/schema-value.bend as V
import ../src/schema-load.bend as L
import ../src/schema.bend as S
import ./schema.bend as T
import ./schema-convert.bend as C

def sameDiagnostic(actual: Maybe<&2, String>, expected: Maybe<&2, String>, label: String) -> IO(Unit):
  match actual expected:
    case Some{actual} Some{expected}: T.assertion(String.eq(actual, expected), "builder diagnostics: " ++ label)
    case _ _: T.assertion(False{}, "builder diagnostics could not be rendered: " ++ label)

def loaded(result: L.Loaded(), checker: S.Schema, +input: V.Value, +expected: Bool, +label: String) -> IO(Unit):
  match result:
    case Fail{_}: T.assertion(False{}, "builder projection failed to compile: " ++ label)
    case Done{+schema}:
      do IO<Unit>:
        +valid : Bool = S.check(schema, input)
        T.assertion((valid && expected) || (Bool.not(valid) && Bool.not(expected)), "builder wire validation: " ++ label)
        sameDiagnostic(Errors.formatNativeValidationFailure("tool", input, E.errors(checker, input)), Errors.formatNativeValidationFailure("tool", input, E.errors(schema, input)), label)

def check(+declaration: D.Declaration, +input: V.Value, raw: V.Value, converted: V.Value, +expected: Bool, +label: String) -> IO(Unit):
  do IO<Unit>:
    T.assertion(V.equal(D.schema(declaration), raw), "builder schema projection: " ++ label)
    +valid : Bool = D.check(declaration, input)
    T.assertion((valid && expected) || (Bool.not(valid) && Bool.not(expected)), "builder typed validation: " ++ label)
    loaded(L.compile(D.schema(declaration)), D.constraint(declaration), input, expected, label)
    C.converted(D.convert(declaration, input), converted, "builder conversion: " ++ label)

def configured(result: D.Configured(), input: V.Value, raw: V.Value, converted: V.Value, expected: Bool, label: String) -> IO(Unit):
  match result:
    case Fail{_}: T.assertion(False{}, "builder options failed: " ++ label)
    case Done{declaration}: check(declaration, input, raw, converted, expected, label)

def normalized(result: Normalize.Outcome(), +declaration: D.Declaration, expected: V.Value) -> IO(Unit):
  match result:
    case Fail{_}: T.assertion(False{}, "builder optional-null normalization failed")
    case Done{+value}:
      do IO<Unit>:
        T.assertion(D.check(declaration, value), "normalized builder arguments satisfy declaration")
        C.converted(D.convert(declaration, value), expected, "builder preserves normalized optional and nullable fields")

def optionalNulls() -> IO(Unit):
  +declaration = D.object(R.Record{
    R.Property{"path", D.required(D.string())} <>
    R.Property{"offset", D.optional(D.number())} <>
    R.Property{"nullable", D.optional(D.union(D.string() <> D.null() <> Nil{}))} <>
    R.Property{"metadata", D.required(D.object(R.Record{R.Property{"enabled", D.optional(D.boolean())} <> Nil{}}))} <> Nil{}})
  input = {V.ObjectValue{R.Record{R.Property{"path", V.Text{"file.txt"}} <> R.Property{"offset", V.Null{}} <> R.Property{"nullable", V.Null{}} <> R.Property{"metadata", V.ObjectValue{R.Record{R.Property{"enabled", V.Null{}} <> Nil{}}}} <> Nil{}}} : V.Value}
  expected = {V.ObjectValue{R.Record{R.Property{"path", V.Text{"file.txt"}} <> R.Property{"nullable", V.Null{}} <> R.Property{"metadata", V.ObjectValue{R.new(V.Value)}} <> Nil{}}} : V.Value}
  normalized(Normalize.normalizeOptionalNulls(input, D.schema(declaration)), declaration, expected)

def main() -> IO(Unit):
  do IO<Unit>:
    +nullable : D.Declaration = D.union(D.number() <> D.null() <> Nil{})
    C.converted(D.convert(nullable, V.Null{}), V.Null{}, "nullable union preserves null")
    C.converted(D.convert(nullable, V.Text{"42"}), V.Number{F.fromU32(42)}, "nullable union still converts numeric text")
    optionalNulls()
    IO.print("PASS native builder nullable unions and optional-null normalization")
