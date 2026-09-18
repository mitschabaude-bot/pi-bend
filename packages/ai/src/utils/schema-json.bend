import Base
import ../types.bend as T
import ../../../runtime/src/schema-value.bend as S
import ../../../runtime/src/record.bend as R

# Convert immutable schema data to the provider's JSON value type.
type Task is Data:
  Value{value: S.Value}
  ArrayItems{remaining: List<&2, S.Value>, built: List<&2, T.JsonValue>}
  ArrayResult{remaining: List<&2, S.Value>, built: List<&2, T.JsonValue>}
  ObjectItems{remaining: List<&2, R.Property<S.Value>>, built: R.Record<T.JsonValue>}
  ObjectResult{key: String, remaining: List<&2, R.Property<S.Value>>, built: R.Record<T.JsonValue>}

# A finite work stack traverses each tree node once.
@unsafe
def convert(tasks: List<&2, Task>, completed: T.JsonValue) -> T.JsonValue:
  match tasks:
    case Nil{}: completed
    case Value{S.Null{}} <> rest: convert(rest, T.JsonNull{})
    case Value{S.Boolean{value}} <> rest: convert(rest, T.JsonBoolean{value})
    case Value{S.Number{value}} <> rest: convert(rest, T.JsonNumber{value})
    case Value{S.Text{value}} <> rest: convert(rest, T.JsonString{value})
    case Value{S.ArrayValue{values}} <> rest: convert(ArrayItems{values, Nil{}} <> rest, completed)
    case Value{S.ObjectValue{properties}} <> rest: convert(ObjectItems{R.entries(S.Value, properties), R.new(T.JsonValue)} <> rest, completed)
    case ArrayItems{Nil{}, built} <> rest: convert(rest, T.JsonArray{List.reverse(&2, T.JsonValue, built)})
    case ArrayItems{head <> tail, built} <> rest: convert(Value{head} <> ArrayResult{tail, built} <> rest, completed)
    case ArrayResult{remaining, built} <> rest: convert(ArrayItems{remaining, completed <> built} <> rest, T.JsonNull{})
    case ObjectItems{Nil{}, built} <> rest: convert(rest, T.JsonObject{built})
    case ObjectItems{R.Property{key, value} <> tail, built} <> rest: convert(Value{value} <> ObjectResult{key, tail, built} <> rest, completed)
    case ObjectResult{key, remaining, built} <> rest: convert(ObjectItems{remaining, R.set(T.JsonValue, built, key, completed)} <> rest, T.JsonNull{})

def toJson(value: S.Value) -> T.JsonValue:
  convert(Value{value} <> Nil{}, T.JsonNull{})
