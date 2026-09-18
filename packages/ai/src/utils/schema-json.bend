import Base
import ../types.bend as T
import ../../../runtime/src/schema-value.bend as S
import ../../../runtime/src/record.bend as R

# Bridge schema data to the canonical JSON domain after its JSON-round-trip
# projection. Errors and an omitted root are distinct from a JSON null value.
type Conversion is Data:
  Converted{value: T.JsonValue}
  RootOmitted{}
  BigIntError{}
  UnsupportedToJSON{}
  InvalidSnapshot{}

type Task<-M: Data> is Data:
  Value{value: S.Value<M>}
  ArrayItems{remaining: List<&2, S.Value<M>>, built: List<&2, T.JsonValue>}
  ArrayResult{remaining: List<&2, S.Value<M>>, built: List<&2, T.JsonValue>}
  ObjectItems{remaining: List<&2, R.Property<S.Property<S.Value<M>>>>, built: R.Record<T.JsonValue>}
  ObjectResult{key: String, remaining: List<&2, R.Property<S.Property<S.Value<M>>>>, built: R.Record<T.JsonValue>}

# A finite work stack traverses the projected tree once. Every expansion consumes
# a node or a list entry; Bend cannot infer this non-structural termination measure.
@unsafe
def convert(-M: Data, tasks: List<&2, Task<M>>, completed: Maybe<&2, T.JsonValue>) -> Conversion:
  match tasks completed:
    case Nil{} Some{value}: Converted{value}
    case Value{S.Null{}} <> rest _: convert(M, rest, Some{T.JsonNull{}})
    case Value{S.Boolean{value}} <> rest _: convert(M, rest, Some{T.JsonBoolean{value}})
    case Value{S.Number{value}} <> rest _: convert(M, rest, Some{T.JsonNumber{value}})
    case Value{S.Text{value}} <> rest _: convert(M, rest, Some{T.JsonString{value}})
    case Value{S.ArrayValue{values}} <> rest _: convert(M, ArrayItems{values, Nil{}} <> rest, None{})
    case Value{S.ObjectValue{properties, Nil{}}} <> rest _: convert(M, ObjectItems{R.entries(S.Property<S.Value<M>>, properties), R.new(T.JsonValue)} <> rest, None{})
    case ArrayItems{Nil{}, built} <> rest _: convert(M, rest, Some{T.JsonArray{List.reverse(&2, T.JsonValue, built)}})
    case ArrayItems{head <> tail, built} <> rest _: convert(M, Value{head} <> ArrayResult{tail, built} <> rest, None{})
    case ArrayResult{remaining, built} <> rest Some{value}: convert(M, ArrayItems{remaining, value <> built} <> rest, None{})
    case ObjectItems{Nil{}, built} <> rest _: convert(M, rest, Some{T.JsonObject{built}})
    case ObjectItems{R.Property{key, S.Property{value, True{}}} <> tail, built} <> rest _: convert(M, Value{value} <> ObjectResult{key, tail, built} <> rest, None{})
    case ObjectResult{key, remaining, built} <> rest Some{value}: convert(M, ObjectItems{remaining, R.set(T.JsonValue, built, key, value)} <> rest, None{})
    case _ _: InvalidSnapshot{}

def fromSnapshot(-M: Data, result: S.Snapshot<M>) -> Conversion:
  match result:
    case S.Projected{None{}}: RootOmitted{}
    case S.Projected{Some{value}}: convert(M, Value{value} <> Nil{}, None{})
    case S.BigIntError{}: BigIntError{}
    case S.UnsupportedToJSON{}: UnsupportedToJSON{}

def toJson(-M: Data, value: S.Value<M>) -> Conversion:
  fromSnapshot(M, S.snapshot(M, value))
