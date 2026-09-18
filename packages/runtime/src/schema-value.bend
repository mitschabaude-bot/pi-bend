import Base
import ./record.bend as R
import ./f64.bend as F
import ./u64.bend as W
import ./big-nat.bend as B
import ./utf16.bend as U

# Data-property schema trees with typed, opaque symbol/callable metadata. This
# represents schema data, not a JavaScript interpreter or arbitrary live object.
type Property<-V: Data> is Data:
  Property{value: V, enumerable: Bool}

type SymbolProperty<-M: Data, -V: Data> is Data:
  SymbolProperty{key: M, value: V}

type Value<-M: Data> is Data:
  Undefined{}
  Null{}
  Boolean{value: Bool}
  Number{value: F.F64}
  Text{value: String}
  Symbol{identity: M}
  Callable{implementation: M}
  BigInteger{negative: Bool, magnitude: B.BigNat}
  ArrayValue{values: List<&2, Value<M>>}
  ObjectValue{properties: R.Record<Property<Value<M>>>, symbols: List<&2, SymbolProperty<M, Value<M>>>}

type Snapshot<-M: Data> is Data:
  Projected{value: Maybe<&2, Value<M>>}
  BigIntError{}
  UnsupportedToJSON{}

# Hooks cannot be dropped like ordinary callable-valued properties. A future
# live-object adapter must invoke them before entering this data-only projection.
type Task<-M: Data> is Data:
  Visit{value: Value<M>}
  InspectObject{properties: R.Record<Property<Value<M>>>, hook: Maybe<&2, Property<Value<M>>>}
  ArrayItems{remaining: List<&2, Value<M>>, built: List<&2, Value<M>>}
  ArrayResult{remaining: List<&2, Value<M>>, built: List<&2, Value<M>>}
  ObjectItems{remaining: List<&2, R.Property<Property<Value<M>>>>, built: R.Record<Property<Value<M>>>}
  ObjectResult{key: String, remaining: List<&2, R.Property<Property<Value<M>>>>, built: R.Record<Property<Value<M>>>}

def arrayValue(-M: Data, value: Maybe<&2, Value<M>>) -> Value<M>:
  match value:
    case None{}: Null{}
    case Some{item}: item

def objectValue(-M: Data, key: String, built: R.Record<Property<Value<M>>>, value: Maybe<&2, Value<M>>) -> R.Record<Property<Value<M>>>:
  match value:
    case None{}: built
    case Some{item}: R.set(Property<Value<M>>, built, key, Property{item, True{}})

def numberValue(-M: Data, value: F.F64, decoded: F.Decoded) -> Value<M>:
  match decoded:
    case F.NotANumber{}: Null{}
    case F.Infinity{_}: Null{}
    case F.Finite{_, _, significand}:
      # JSON.stringify(-0) followed by JSON.parse produces positive zero.
      Number{Bool.pick(F.F64, W.equal(significand, W.zero()), F.fromU32(0), value)}


# This finite-tree traversal terminates by consuming nodes and list entries.
# The explicit result/work stacks are not a structural measure Bend can infer.
@unsafe
def project(-M: Data, tasks: List<&2, Task<M>>, completed: Maybe<&2, Value<M>>) -> Snapshot<M>:
  match tasks:
    case Nil{}: Projected{completed}
    case Visit{Undefined{}} <> rest: project(M, rest, None{})
    case Visit{Symbol{_}} <> rest: project(M, rest, None{})
    case Visit{Callable{_}} <> rest: project(M, rest, None{})
    case Visit{BigInteger{_, _}} <> _: BigIntError{}
    case Visit{Null{}} <> rest: project(M, rest, Some{Null{}})
    case Visit{Boolean{value}} <> rest: project(M, rest, Some{Boolean{value}})
    case Visit{Number{+value}} <> rest: project(M, rest, Some{numberValue(M, value, F.decode(value))})
    case Visit{Text{value}} <> rest: project(M, rest, Some{Text{U.normalize(value)}})
    case Visit{ArrayValue{values}} <> rest: project(M, ArrayItems{values, Nil{}} <> rest, None{})
    case Visit{ObjectValue{+properties, _}} <> rest: project(M, InspectObject{properties, R.get(Property<Value<M>>, properties, "toJSON")} <> rest, None{})
    case InspectObject{_, Some{Property{Callable{_}, _}}} <> _: UnsupportedToJSON{}
    case InspectObject{properties, _} <> rest: project(M, ObjectItems{R.entries(Property<Value<M>>, properties), R.new(Property<Value<M>>)} <> rest, None{})
    case ArrayItems{Nil{}, built} <> rest: project(M, rest, Some{ArrayValue{List.reverse(&2, Value<M>, built)}})
    case ArrayItems{head <> tail, built} <> rest: project(M, Visit{head} <> ArrayResult{tail, built} <> rest, None{})
    case ArrayResult{remaining, built} <> rest: project(M, ArrayItems{remaining, arrayValue(M, completed) <> built} <> rest, None{})
    case ObjectItems{Nil{}, built} <> rest: project(M, rest, Some{ObjectValue{built, Nil{}}})
    case ObjectItems{R.Property{_, Property{_, False{}}} <> tail, built} <> rest: project(M, ObjectItems{tail, built} <> rest, None{})
    case ObjectItems{R.Property{key, Property{value, True{}}} <> tail, built} <> rest: project(M, Visit{value} <> ObjectResult{key, tail, built} <> rest, None{})
    case ObjectResult{key, remaining, built} <> rest: project(M, ObjectItems{remaining, objectValue(M, key, built, completed)} <> rest, None{})

# Project JSON-visible schema data. Root omissions stay distinct from null;
# callers that need JSON.parse(JSON.stringify(root)) must reject a missing root.
def snapshot(-M: Data, value: Value<M>) -> Snapshot<M>:
  project(M, Visit{value} <> Nil{}, None{})
