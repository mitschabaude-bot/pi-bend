import Base
import ../src/utils/validation.bend as Validation
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/src/u64.bend as W
import ../../runtime/src/big-nat.bend as B

def sameBool(+a: Bool, +b: Bool) -> Bool: (a && b) || (Bool.not(a) && Bool.not(b))

type Comparison is Data:
  Values{left: V.Value<U32>, right: V.Value<U32>}
  Arrays{left: List<&2, V.Value<U32>>, right: List<&2, V.Value<U32>>}
  Objects{left: List<&2, R.Property<V.Property<V.Value<U32>>>>, right: List<&2, R.Property<V.Property<V.Value<U32>>>>}
  Symbols{left: List<&2, V.SymbolProperty<U32, V.Value<U32>>>, right: List<&2, V.SymbolProperty<U32, V.Value<U32>>>}

# Finite input trees are consumed through explicit traversal stacks.
@unsafe def equal(work: List<&2, Comparison>) -> Bool:
  match work:
    case Nil{}: True{}
    case Values{V.Undefined{}, V.Undefined{}} <> rest: equal(rest)
    case Values{V.Null{}, V.Null{}} <> rest: equal(rest)
    case Values{V.Boolean{a}, V.Boolean{b}} <> rest: sameBool(a, b) && equal(rest)
    case Values{V.Number{a}, V.Number{b}} <> rest: W.equal(F.toBits(a), F.toBits(b)) && equal(rest)
    case Values{V.Text{a}, V.Text{b}} <> rest: String.eq(a, b) && equal(rest)
    case Values{V.Symbol{a}, V.Symbol{b}} <> rest: U32.is_eq(a, b) && equal(rest)
    case Values{V.Callable{a}, V.Callable{b}} <> rest: U32.is_eq(a, b) && equal(rest)
    case Values{V.BigInteger{sa, a}, V.BigInteger{sb, b}} <> rest: sameBool(sa, sb) && B.equal(a, b) && equal(rest)
    case Values{V.ArrayValue{a}, V.ArrayValue{b}} <> rest: equal(Arrays{a, b} <> rest)
    case Values{V.ObjectValue{a, sa}, V.ObjectValue{b, sb}} <> rest: equal(Objects{R.entries(V.Property<V.Value<U32>>, a), R.entries(V.Property<V.Value<U32>>, b)} <> Symbols{sa, sb} <> rest)
    case Arrays{Nil{}, Nil{}} <> rest: equal(rest)
    case Arrays{a <> xs, b <> ys} <> rest: equal(Values{a, b} <> Arrays{xs, ys} <> rest)
    case Objects{Nil{}, Nil{}} <> rest: equal(rest)
    case Objects{R.Property{ka, V.Property{a, ea}} <> xs, R.Property{kb, V.Property{b, eb}} <> ys} <> rest: String.eq(ka, kb) && sameBool(ea, eb) && equal(Values{a, b} <> Objects{xs, ys} <> rest)
    case Symbols{Nil{}, Nil{}} <> rest: equal(rest)
    case Symbols{V.SymbolProperty{ka, a} <> xs, V.SymbolProperty{kb, b} <> ys} <> rest: U32.is_eq(ka, kb) && equal(Values{a, b} <> Symbols{xs, ys} <> rest)
    case _: False{}

def checked(result: Validation.Coercion(U32), expected: V.Value<U32>, label: String) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "number formatting failed")
    case Done{actual}: Bool.pick(IO(Unit), equal(Values{actual, expected} <> Nil{}), IO.pure(Unit, Unit{}), IO.die(Unit, 1, label))

def check(value: V.Value<U32>, kind: String, expected: V.Value<U32>, label: String) -> IO(Unit):
  checked(Validation.coercePrimitiveByType(U32, value, kind), expected, label)

def checkTypes(value: V.Value<U32>, types: List<&2, String>, expected: V.Value<U32>, label: String) -> IO(Unit):
  checked(Validation.coerceSchemaTypes(U32, value, types), expected, label)
