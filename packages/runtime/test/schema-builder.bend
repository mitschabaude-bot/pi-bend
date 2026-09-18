import Base
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

def main() -> IO(Unit):
  do IO<Unit>:
    +nullable : D.Declaration = D.union(D.number() <> D.null() <> Nil{})
    C.converted(D.convert(nullable, V.Null{}), V.Null{}, "nullable union preserves null")
    C.converted(D.convert(nullable, V.Text{"42"}), V.Number{F.fromU32(42)}, "nullable union still converts numeric text")
    IO.print("PASS native builder nullable union behavior")
