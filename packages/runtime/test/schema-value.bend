import Base
import ../src/schema-value.bend as V
import ../src/record.bend as R
import ../src/f64.bend as F
import ../src/u64.bend as W

type Comparison is Data:
  Values{left: V.Value<U32>, right: V.Value<U32>}
  Arrays{left: List<&2, V.Value<U32>>, right: List<&2, V.Value<U32>>}
  Objects{left: List<&2, R.Property<V.Property<V.Value<U32>>>>, right: List<&2, R.Property<V.Property<V.Value<U32>>>>}

# Compare every node and field against independent expected trees, including
# the absence of symbols and the restored enumerability of cloned properties.
@unsafe
def equal(work: List<&2, Comparison>) -> Bool:
  match work:
    case Nil{}: True{}
    case Values{V.Null{}, V.Null{}} <> rest: equal(rest)
    case Values{V.Boolean{+a}, V.Boolean{+b}} <> rest: ((a && b) || (Bool.not(a) && Bool.not(b))) && equal(rest)
    case Values{V.Number{a}, V.Number{b}} <> rest: W.equal(F.toBits(a), F.toBits(b)) && equal(rest)
    case Values{V.Text{a}, V.Text{b}} <> rest: String.eq(a, b) && equal(rest)
    case Values{V.ArrayValue{a}, V.ArrayValue{b}} <> rest: equal(Arrays{a, b} <> rest)
    case Values{V.ObjectValue{a, Nil{}}, V.ObjectValue{b, Nil{}}} <> rest: equal(Objects{R.entries(V.Property<V.Value<U32>>, a), R.entries(V.Property<V.Value<U32>>, b)} <> rest)
    case Arrays{Nil{}, Nil{}} <> rest: equal(rest)
    case Arrays{a <> xs, b <> ys} <> rest: equal(Values{a, b} <> Arrays{xs, ys} <> rest)
    case Objects{Nil{}, Nil{}} <> rest: equal(rest)
    case Objects{R.Property{keyA, V.Property{a, True{}}} <> xs, R.Property{keyB, V.Property{b, True{}}} <> ys} <> rest: String.eq(keyA, keyB) && equal(Values{a, b} <> Objects{xs, ys} <> rest)
    case _: False{}

def same(actual: V.Snapshot<U32>, expected: V.Snapshot<U32>) -> Bool:
  match actual expected:
    case V.Projected{None{}} V.Projected{None{}}: True{}
    case V.Projected{Some{a}} V.Projected{Some{b}}: equal(Values{a, b} <> Nil{})
    case V.BigIntError{} V.BigIntError{}: True{}
    case V.UnsupportedToJSON{} V.UnsupportedToJSON{}: True{}
    case _ _: False{}

def check(input: V.Value<U32>, expected: V.Snapshot<U32>, label: String) -> IO(Unit):
  Bool.pick(IO(Unit), same(V.snapshot(U32, input), expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, label))


def nested(count: Nat, value: V.Value<U32>) -> V.Value<U32>:
  match count:
    case 0n: value
    case 1n+n: nested(n, V.ArrayValue{value <> Nil{}})
