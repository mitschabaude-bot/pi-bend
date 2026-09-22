import Base
import ../src/schema.bend as C
import ../src/schema-value.bend as V
import ../src/f64.bend as F
import ../src/u64.bend as W
import ./schema.bend as T
import ../src/record.bend as R

@unsafe
def compareExact(work: Maybe<&2, List<&2, V.Comparison>>) -> Bool:
  match work:
    case None{}: False{}
    case Some{Nil{}}: True{}
    case Some{V.Values{V.Null{}, V.Null{}} <> rest}: compareExact(Some{rest})
    case Some{V.Values{V.Boolean{+a}, V.Boolean{+b}} <> rest}: ((a && b) || (Bool.not(a) && Bool.not(b))) && compareExact(Some{rest})
    case Some{V.Values{V.Number{a}, V.Number{b}} <> rest}: W.equal(F.toBits(a), F.toBits(b)) && compareExact(Some{rest})
    case Some{V.Values{V.Text{a}, V.Text{b}} <> rest}: String.eq(a, b) && compareExact(Some{rest})
    case Some{V.Values{V.ArrayValue{a}, V.ArrayValue{b}} <> rest}: compareExact(Some{V.Arrays{a, b} <> rest})
    case Some{V.Values{V.ObjectValue{a}, V.ObjectValue{b}} <> rest}: compareExact(Some{V.Fields{R.entries(V.Value, a), b} <> rest})
    case Some{V.Arrays{Nil{}, Nil{}} <> rest}: compareExact(Some{rest})
    case Some{V.Arrays{a <> xs, b <> ys} <> rest}: compareExact(Some{V.Values{a, b} <> V.Arrays{xs, ys} <> rest})
    case Some{V.Fields{Nil{}, R.Record{Nil{}}} <> rest}: compareExact(Some{rest})
    case Some{V.Fields{R.Property{+key, value} <> tail, +other} <> rest}: compareExact(V.matchedField(value, R.get(V.Value, other, key), V.Fields{tail, R.remove(V.Value, other, key)} <> rest))
    case _: False{}

def same(actual: V.Value, expected: V.Value) -> Bool:
  compareExact(Some{V.Values{actual, expected} <> Nil{}})

def converted(result: C.Converted(), expected: V.Value, label: String) -> IO(Unit):
  match result:
    case Done{actual}: T.assertion(same(actual, expected), label)
    case Fail{_}: T.assertion(False{}, "builder conversion failed: " ++ label)

def check(kind: C.Primitive, input: V.Value, expected: V.Value, label: String) -> IO(Unit):
  converted(C.convertConvert(kind, input), expected, label)

def nestedPolicy(depth: Nat) -> C.Policy:
  match depth:
    case Zero{}: C.Scalar{C.ToNumber{}}
    case Succ{rest}: C.ArrayItems{nestedPolicy(rest)}

def nestedValue(depth: Nat) -> V.Value:
  match depth:
    case Zero{}: V.Number{F.fromU32(42)}
    case Succ{rest}: V.ArrayValue{nestedValue(rest) <> Nil{}}

def main() -> IO(Unit):
  do IO<Unit>:
    +negativeZero : F.F64 = F.fromBits(2147483648, 0)
    T.assertion(W.equal(F.toBits(F.truncate(F.negate(F.divide(F.fromU32(1), F.fromU32(2))))), F.toBits(negativeZero)), "truncate preserves negative zero")
    T.assertion(Bool.not(same(V.ArrayValue{V.Number{negativeZero} <> Nil{}}, V.ArrayValue{V.Number{F.fromU32(0)} <> Nil{}})), "conversion oracle distinguishes nested signed zero")
    +special : F.F64 = F.fromBits(2146959412, 12345)
    T.assertion(W.equal(F.toBits(F.truncate(special)), F.toBits(special)), "truncate preserves NaN payload bits")
    +infinity : F.F64 = F.infinity(True{})
    T.assertion(W.equal(F.toBits(F.truncate(infinity)), F.toBits(infinity)), "truncate preserves infinity")
    converted(C.convertConvert(C.ToString{}, V.Number{special}), V.Text{"NaN"}, "builder numeric string conversion")
    converted(C.convertConvert(C.ToString{}, V.Number{infinity}), V.Text{"-Infinity"}, "builder infinite string conversion")
    converted(C.convertConvert(C.ToInteger{}, V.Text{"-0n"}), V.Number{F.fromU32(0)}, "decimal integer literal zero has no negative sign")
    converted(C.apply(nestedPolicy(256n), V.Text{"42"}), nestedValue(256n), "deeply nested array conversion")
    IO.print("PASS native builder conversion IEEE values, exact integer literals and nested policies")
