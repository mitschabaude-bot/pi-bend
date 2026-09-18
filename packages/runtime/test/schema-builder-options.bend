import Base
import ../src/schema-builder.bend as D
import ../src/schema-value.bend as V
import ../src/record.bend as R
import ../src/f64.bend as F
import ../src/schema-load.bend as L
import ./schema.bend as T
import ./schema-convert.bend as C

def unsupported(result: D.Configured(), expected: String) -> Bool:
  match result:
    case Fail{D.UnsupportedOption{name}}: String.eq(name, expected)
    case _: False{}

def malformed(result: D.Configured()) -> Bool:
  match result:
    case Fail{D.InvalidOptionSchema{L.Error{key <> Nil{}, L.InvalidSchema{_}}}}: String.eq(key, "minimum")
    case _: False{}

def replaced(result: D.Configured(), original: D.Declaration) -> IO(Unit):
  match result:
    case Fail{_}: T.assertion(False{}, "replace option failed")
    case Done{+declaration}:
      do IO<Unit>:
        T.assertion(D.check(original, V.Number{F.fromU32(1)}), "previous constrained declaration remains valid")
        T.assertion(Bool.not(D.check(declaration, V.Number{F.fromU32(1)})), "replacement updates compiled constraint")
        T.assertion(D.check(declaration, V.Number{F.fromU32(2)}), "replacement retains inclusive bound")

def constrained(result: D.Configured(), original: D.Declaration) -> IO(Unit):
  match result:
    case Fail{_}: T.assertion(False{}, "constrain declaration failed")
    case Done{+declaration}:
      do IO<Unit>:
        T.assertion(D.check(original, V.Number{F.fromU32(0)}), "original declaration remains unconstrained")
        T.assertion(Bool.not(D.check(declaration, V.Number{F.fromU32(0)})), "compiled minimum rejects zero")
        C.converted(D.convert(declaration, V.Text{"0"}), V.Number{F.fromU32(0)}, "conversion remains independent of final validation")
        replaced(D.withOptions(declaration, R.Record{R.Property{"minimum", V.Number{F.fromU32(2)}} <> Nil{}}), declaration)

def nestedUnion(result: D.Configured()) -> IO(Unit):
  match result:
    case Fail{_}: T.assertion(False{}, "configure nested array failed")
    case Done{declaration}:
      C.converted(D.convert(D.union(declaration <> D.tuple(D.number() <> Nil{}) <> Nil{}), V.Text{"1"}), V.ArrayValue{V.Number{F.fromU32(1)} <> Nil{}}, "union candidates use updated constraints and whole-union acceptance")

def outerUnion(result: D.Configured()) -> IO(Unit):
  match result:
    case Fail{_}: T.assertion(False{}, "configure union failed")
    case Done{+declaration}:
      do IO<Unit>:
        C.converted(D.convert(declaration, V.ArrayValue{V.Text{"1"} <> Nil{}}), V.ArrayValue{V.Text{"1"} <> Nil{}}, "reject all candidates violating union-level minimum")
        C.converted(D.convert(declaration, V.ArrayValue{V.Number{F.fromU32(1)} <> Nil{}}), V.ArrayValue{V.Number{F.fromU32(1)} <> Nil{}}, "original branch match is preserved even when outer constraint fails")
        T.assertion(Bool.not(D.check(declaration, V.ArrayValue{V.Number{F.fromU32(1)} <> Nil{}})), "final validation still enforces outer constraint")

def stringBounds(result: D.Configured()) -> IO(Unit):
  match result:
    case Fail{_}: T.assertion(False{}, "configure string bounds failed")
    case Done{+declaration}:
      do IO<Unit>:
        T.assertion(D.check(declaration, V.Text{"e\u{301}"}), "schema combining sequence counts as one cluster")
        T.assertion(Bool.not(D.check(declaration, V.Text{"ab"})), "configured string rejects excess clusters")
        C.converted(D.convert(declaration, V.Number{F.fromU32(1)}), V.Text{"1"}, "string bounds preserve builder scalar conversion")

def main() -> IO(Unit):
  do IO<Unit>:
    T.assertion(unsupported(D.withOptions(D.number(), R.Record{R.Property{"type", V.Text{"string"}} <> Nil{}}), "type"), "structural overrides are explicit unsupported options")
    T.assertion(unsupported(D.withOptions(D.object(R.new(D.Field)), R.Record{R.Property{"additionalProperties", D.schema(D.string())} <> Nil{}}), "additionalProperties"), "schema-valued additional conversion remains pending")
    T.assertion(malformed(D.withOptions(D.number(), R.Record{R.Property{"minimum", V.Text{"bad"}} <> Nil{}})), "malformed option preserves schema error path")
    stringBounds(D.withOptions(D.string(), R.Record{R.Property{"minLength", V.Number{F.fromU32(1)}} <> R.Property{"maxLength", V.Number{F.fromU32(1)}} <> Nil{}}))
    +original : D.Declaration = D.number()
    constrained(D.withOptions(original, R.Record{R.Property{"minimum", V.Number{F.fromU32(1)}} <> Nil{}}), original)
    nestedUnion(D.withOptions(D.array(D.number()), R.Record{R.Property{"minItems", V.Number{F.fromU32(2)}} <> Nil{}}))
    outerUnion(D.withOptions(D.union(D.tuple(D.number() <> Nil{}) <> D.array(D.number()) <> Nil{}), R.Record{R.Property{"minItems", V.Number{F.fromU32(2)}} <> Nil{}}))
    IO.print("PASS builder option errors, immutable replacement and nested composition")
