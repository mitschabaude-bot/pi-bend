import Base
import ./ref.bend as Ref
import ./record.bend as Record
import ./f64.bend as F
import ./big-nat.bend as B
import ./utf16.bend as U

# Shared ordinary-object storage. Metadata supplies stable symbol/function
# identities; it is not serialized or replaced with a string identifier.
type Descriptor<-M: Data, -V: Data> is Data:
  DataProperty{value: V, writable: Bool, enumerable: Bool, configurable: Bool}
  AccessorProperty{get: Maybe<&2, M>, set: Maybe<&2, M>, enumerable: Bool, configurable: Bool}

type SymbolProperty<-M: Data, -V: Data> is Data:
  SymbolProperty{key: M, descriptor: Descriptor<M, V>}

type ObjectState<-M: Data, -V: Data> is Data:
  ObjectState{properties: Record.Record<Descriptor<M, V>>, symbols: List<&2, SymbolProperty<M, V>>, prototype: Maybe<&2, V>, extensible: Bool}

# Sparse array indices are descriptors in the same property table as ordinary
# keys. Length is independent of present indices, so a hole is not undefined.
# Valid storage excludes "length" from the property table, and every present
# array index is below length. Future mutation operations must enforce these.
type ArrayState<-M: Data, -V: Data> is Data:
  ArrayState{object: ObjectState<M, V>, length: U32, lengthWritable: Bool}

type Value<-M: Data> is Data:
  Undefined{}
  Null{}
  Boolean{value: Bool}
  Number{value: F.F64}
  Text{value: String}
  Symbol{identity: M}
  Callable{implementation: M}
  BigInteger{negative: Bool, magnitude: B.BigNat}
  ObjectValue{storage: Ref.Ref<ObjectState<M, Value<M>>>}
  ArrayValue{storage: Ref.Ref<ArrayState<M, Value<M>>>}

def ObjectStorage(-M: Data) -> Data: ObjectState<M, Value<M>>
def ArrayStorage(-M: Data) -> Data: ArrayState<M, Value<M>>

def emptyObjectState(-M: Data, -V: Data, prototype: Maybe<&2, V>) -> ObjectState<M, V>:
  ObjectState{Record.new(Descriptor<M, V>), Nil{}, prototype, True{}}

# None is a null prototype. Standard realm prototypes must be passed explicitly.
# Owners retain and retire storage references; recursive disposal would be wrong
# for aliased/cyclic graphs, so these factories do not install a tree lifetime.
def newObject(-M: Data, prototype: Maybe<&2, Value<M>>) -> IO(Ref.Ref<ObjectStorage(M)>):
  Ref.new(ObjectStorage(M), emptyObjectState(M, Value<M>, prototype))

def newArray(-M: Data, prototype: Maybe<&2, Value<M>>) -> IO(Ref.Ref<ArrayStorage(M)>):
  Ref.new(ArrayStorage(M), ArrayState{emptyObjectState(M, Value<M>, prototype), 0, True{}})

def sameBoolean(+a: Bool, +b: Bool) -> Bool: (a && b) || (Bool.not(a) && Bool.not(b))

def equalNumber(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case _: False{}

# ECMAScript strict equality never reads object storage or invokes user code.
# The supplied metadata comparator must compare identities without side effects.
def strictEqual(-M: Data, a: Value<M>, b: Value<M>, sameMetadata: M -> M -> Bool) -> Bool:
  match a b:
    case Undefined{} Undefined{}: True{}
    case Null{} Null{}: True{}
    case Boolean{x} Boolean{y}: sameBoolean(x, y)
    case Number{x} Number{y}: equalNumber(F.compare(x, y))
    case Text{x} Text{y}: String.eq(U.normalize(x), U.normalize(y))
    case Symbol{x} Symbol{y}: sameMetadata(x, y)
    case Callable{x} Callable{y}: sameMetadata(x, y)
    case BigInteger{sx, +x} BigInteger{sy, +y}: B.equal(x, y) && (sameBoolean(sx, sy) || (B.isZero(x) && B.isZero(y)))
    case ObjectValue{x} ObjectValue{y}: Ref.same(ObjectStorage(M), x, y)
    case ArrayValue{x} ArrayValue{y}: Ref.same(ArrayStorage(M), x, y)
    case _ _: False{}

def typeOf(-M: Data, value: Value<M>) -> String:
  match value:
    case Undefined{}: "undefined"
    case Null{}: "object"
    case Boolean{_}: "boolean"
    case Number{_}: "number"
    case Text{_}: "string"
    case Symbol{_}: "symbol"
    case Callable{_}: "function"
    case BigInteger{_, _}: "bigint"
    case ObjectValue{_}: "object"
    case ArrayValue{_}: "object"
