import Base
import ../src/schema-convert.bend as C
import ../src/schema-value.bend as V
import ../src/f64.bend as F
import ../src/u64.bend as W
import ./schema.bend as T

def same(actual: V.Value, expected: V.Value) -> Bool:
  match actual expected:
    case V.Number{a} V.Number{b}: W.equal(F.toBits(a), F.toBits(b))
    case a b: V.equal(a, b)

def converted(result: C.Converted(), expected: V.Value, label: String) -> IO(Unit):
  match result:
    case Done{actual}: T.assertion(same(actual, expected), label)
    case Fail{_}: T.assertion(False{}, "builder primitive formatting failed: " ++ label)

def check(kind: C.Primitive, input: V.Value, expected: V.Value, label: String) -> IO(Unit):
  converted(C.convert(kind, input), expected, label)

def main() -> IO(Unit):
  do IO<Unit>:
    +negativeZero : F.F64 = F.fromBits(2147483648, 0)
    T.assertion(W.equal(F.toBits(F.truncate(F.negate(F.divide(F.fromU32(1), F.fromU32(2))))), F.toBits(negativeZero)), "truncate preserves negative zero")
    +special : F.F64 = F.fromBits(2146959412, 12345)
    T.assertion(W.equal(F.toBits(F.truncate(special)), F.toBits(special)), "truncate preserves NaN payload bits")
    +infinity : F.F64 = F.infinity(True{})
    T.assertion(W.equal(F.toBits(F.truncate(infinity)), F.toBits(infinity)), "truncate preserves infinity")
    converted(C.convert(C.ToString{}, V.Number{special}), V.Text{"NaN"}, "builder numeric string conversion")
    converted(C.convert(C.ToString{}, V.Number{infinity}), V.Text{"-Infinity"}, "builder infinite string conversion")
    converted(C.convert(C.ToInteger{}, V.Text{"-0n"}), V.Number{F.fromU32(0)}, "decimal integer literal zero has no negative sign")
    IO.print("PASS native builder conversion IEEE values and exact integer literals")
