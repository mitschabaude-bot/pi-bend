import Base
import ./record.bend as R
import ./f64.bend as F

# Immutable JSON-compatible data for schemas and tool arguments. Executable
# callbacks and optional fields belong to their enclosing typed Bend records.
type Value is Data:
  Null{}
  Boolean{value: Bool}
  Number{value: F64}
  Text{value: String}
  ArrayValue{values: List<&2, Value>}
  ObjectValue{properties: R.Record<Value>}

type Comparison is Data:
  Values{left: Value, right: Value}
  Arrays{left: List<&2, Value>, right: List<&2, Value>}
  Fields{remaining: List<&2, R.Property<Value>>, other: R.Record<Value>}

def matchedField(value: Value, other: Maybe<&2, Value>, rest: List<&2, Comparison>) -> Maybe<&2, List<&2, Comparison>>:
  match other:
    case None{}: None{}
    case Some{right}: Some{Values{value, right} <> rest}

# Each frame consumes a finite value, array element, or dictionary entry.
@unsafe
def compare(work: Maybe<&2, List<&2, Comparison>>) -> Bool:
  match work:
    case None{}: False{}
    case Some{Nil{}}: True{}
    case Some{Values{Null{}, Null{}} <> rest}: compare(Some{rest})
    case Some{Values{Boolean{+a}, Boolean{+b}} <> rest}: ((a && b) || (Bool.not(a) && Bool.not(b))) && compare(Some{rest})
    case Some{Values{Number{a}, Number{b}} <> rest}: F.isEqual(F.compare(a, b)) && compare(Some{rest})
    case Some{Values{Text{a}, Text{b}} <> rest}: String.eq(a, b) && compare(Some{rest})
    case Some{Values{ArrayValue{a}, ArrayValue{b}} <> rest}: compare(Some{Arrays{a, b} <> rest})
    case Some{Values{ObjectValue{a}, ObjectValue{b}} <> rest}: compare(Some{Fields{R.entries(Value, a), b} <> rest})
    case Some{Arrays{Nil{}, Nil{}} <> rest}: compare(Some{rest})
    case Some{Arrays{a <> xs, b <> ys} <> rest}: compare(Some{Values{a, b} <> Arrays{xs, ys} <> rest})
    case Some{Fields{Nil{}, R.Record{Nil{}}} <> rest}: compare(Some{rest})
    case Some{Fields{R.Property{+key, value} <> tail, +other} <> rest}: compare(matchedField(value, R.get(Value, other, key), Fields{tail, R.remove(Value, other, key)} <> rest))
    case _: False{}

def equal(left: Value, right: Value) -> Bool:
  compare(Some{Values{left, right} <> Nil{}})
