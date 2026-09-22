import Base
import ../src/schema.bend as Text
import ../src/big-nat.bend as B
import ../src/schema.bend as L
import ../src/schema-value.bend as V
import ../src/record.bend as R
import ../src/f64.bend as F
import ./schema.bend as T

def check(text: String, expected: U32, label: String) -> IO(Unit):
  T.assertion(Cmp.is_eq(B.compare(Text.length(text), B.fromU32(expected))), label)

def malformed(result: L.Loaded(), expected: String) -> Bool:
  match result:
    case Fail{L.LoadError{key <> Nil{}, L.InvalidSchema{_}}}: String.eq(key, expected)
    case _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    T.assertion(malformed(L.compile(V.ObjectValue{R.Record{R.Property{"minLength", V.Number{F.negate(F.fromU32(1))}} <> Nil{}}}), "minLength"), "negative string bound rejects with keyword path")
    T.assertion(malformed(L.compile(V.ObjectValue{R.Record{R.Property{"maxLength", V.Number{F.divide(F.fromU32(1), F.fromU32(2))}} <> Nil{}}}), "maxLength"), "fractional string bound rejects with keyword path")
    T.assertion(malformed(L.compile(V.ObjectValue{R.Record{R.Property{"minLength", V.Text{"1"}} <> Nil{}}}), "minLength"), "string-valued bound rejects with keyword path")
    IO.print("PASS native string length schema errors")
