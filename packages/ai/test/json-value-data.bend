import Base
import ../src/types.bend as T
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R

# Test-only structural projection; avoids comparing JSON property order.
type Task is Data:
  Value{value: T.JsonValue}
  ArrayItems{values: List<&2, T.JsonValue>, built: List<&2, V.Value>}
  ArrayResult{values: List<&2, T.JsonValue>, built: List<&2, V.Value>}
  ObjectItems{values: List<&2, R.Property<T.JsonValue>>, built: R.Record<V.Value>}
  ObjectResult{key: String, values: List<&2, R.Property<T.JsonValue>>, built: R.Record<V.Value>}

# Each frame visits one node of a finite acyclic JSON tree.
@unsafe
def convert(tasks: List<&2, Task>, completed: V.Value) -> V.Value:
  match tasks:
    case Nil{}: completed
    case Value{T.JsonNull{}} <> rest: convert(rest, V.Null{})
    case Value{T.JsonBoolean{value}} <> rest: convert(rest, V.Boolean{value})
    case Value{T.JsonNumber{scalar}} <> rest: convert(rest, V.Number{scalar})
    case Value{T.JsonString{text}} <> rest: convert(rest, V.Text{text})
    case Value{T.JsonArray{values}} <> rest: convert(ArrayItems{values, Nil{}} <> rest, completed)
    case Value{T.JsonObject{fields}} <> rest: convert(ObjectItems{R.entries(T.JsonValue, fields), R.new(V.Value)} <> rest, completed)
    case ArrayItems{Nil{}, built} <> rest: convert(rest, V.ArrayValue{List.reverse(&2, V.Value, built)})
    case ArrayItems{head <> tail, built} <> rest: convert(Value{head} <> ArrayResult{tail, built} <> rest, completed)
    case ArrayResult{values, built} <> rest: convert(ArrayItems{values, completed <> built} <> rest, V.Null{})
    case ObjectItems{Nil{}, built} <> rest: convert(rest, V.ObjectValue{built})
    case ObjectItems{R.Property{key, value} <> tail, built} <> rest: convert(Value{value} <> ObjectResult{key, tail, built} <> rest, completed)
    case ObjectResult{key, values, built} <> rest: convert(ObjectItems{values, R.set(V.Value, built, key, completed)} <> rest, V.Null{})

def project(value: T.JsonValue) -> V.Value: convert(Value{value} <> Nil{}, V.Null{})
