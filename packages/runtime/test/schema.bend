import Base
import ../src/schema.bend as S
import ../src/schema-value.bend as V
import ../src/record.bend as R
import ../src/f64.bend as F

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def ordinaryKey(+key: String) -> IO(Unit):
  do IO<Unit>:
    +schema : S.Schema = S.Object{R.Record{R.Property{key, S.JsonKind{S.IntegerType{}}} <> Nil{}}, key <> Nil{}, S.Reject{}}
    +empty : V.Value = V.ObjectValue{R.new(V.Value)}
    +populated : V.Value = V.ObjectValue{R.Record{R.Property{key, V.Number{F.fromU32(1)}} <> Nil{}}}
    assertion(Bool.not(S.check(schema, empty)), "no implicit inherited required field")
    assertion(S.check(schema, populated), "explicit dictionary key must validate")
    assertion(V.equal(empty, V.ObjectValue{R.new(V.Value)}), "checking must leave original values unchanged")

# The first two arms both match. Remaining arms need not be evaluated.
def alternatives(count: Nat) -> List<&2, S.Schema>:
  match count:
    case Zero{}: Nil{}
    case Succ{rest}: S.Accept{} <> alternatives(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    ordinaryKey("__proto__")
    ordinaryKey("constructor")
    ordinaryKey("toString")
    ordinaryKey("01")
    ordinaryKey("1")
    assertion(S.check(S.All{Nil{}}, V.Null{}), "empty conjunction")
    assertion(Bool.not(S.check(S.Any{Nil{}}, V.Null{})), "empty disjunction")
    assertion(Bool.not(S.check(S.One{Nil{}}, V.Null{})), "empty exclusive disjunction")
    assertion(S.check(S.One{S.Reject{} <> S.Accept{} <> S.Reject{} <> Nil{}}, V.Null{}), "exactly one matching arm")
    assertion(Bool.not(S.check(S.One{alternatives(1000n)}, V.Null{})), "oneOf counts multiple matches")
    assertion(Bool.not(S.check(S.JsonKind{S.NumberType{}}, V.Number{F.nan()})), "NaN is not a JSON number")
    assertion(Bool.not(S.check(S.JsonKind{S.NumberType{}}, V.Number{F.fromBits(2146435072, 0)})), "infinity is not a JSON number")
    assertion(Bool.not(S.check(S.JsonKind{S.IntegerType{}}, V.Number{F.fromBits(4293918720, 0)})), "negative infinity is not an integer")
    assertion(S.check(S.JsonKind{S.IntegerType{}}, V.Number{F.fromBits(2147483648, 0)}), "negative zero is an integer")
    +requiredNull : S.Schema = S.Object{R.Record{R.Property{"x", S.JsonKind{S.NullType{}}} <> Nil{}}, "x" <> Nil{}, S.Accept{}}
    assertion(S.check(requiredNull, V.ObjectValue{R.Record{R.Property{"x", V.Null{}} <> Nil{}}}), "required field may explicitly accept null")
    assertion(Bool.not(S.check(requiredNull, V.ObjectValue{R.new(V.Value)})), "missing is not explicit null")
    IO.print("PASS native schema dictionary, immutable value, boolean-algebra and numeric edge cases")
