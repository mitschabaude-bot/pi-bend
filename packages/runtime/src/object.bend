import Base
import ./value.bend as V
import ./ref.bend as Ref
import ./record.bend as Record
import ./f64.bend as F

type PropertyKey<-M: Data> is Data:
  StringKey{value: String}
  SymbolKey{identity: M}

type ObjectError is Data:
  NotObject{}
  UnsupportedCallableObject{}

def symbolKeys(-M: Data, symbols: List<&2, V.SymbolProperty<M, V.Value<M>>>) -> List<&2, PropertyKey<M>>:
  match symbols:
    case Nil{}: Nil{}
    case V.SymbolProperty{key, _} <> rest: SymbolKey{key} <> symbolKeys(M, rest)

def stringKeys(-M: Data, properties: List<&2, Record.Property<V.Descriptor<M, V.Value<M>>>>, suffix: List<&2, PropertyKey<M>>) -> List<&2, PropertyKey<M>>:
  match properties:
    case Nil{}: suffix
    case Record.Property{key, _} <> rest: StringKey{key} <> stringKeys(M, rest, suffix)

def objectKeys(-M: Data, value: V.ObjectStorage(M)) -> List<&2, PropertyKey<M>>:
  match value:
    case V.ObjectState{properties, symbols, _, _}: stringKeys(M, Record.entries(V.Descriptor<M, V.Value<M>>, properties), symbolKeys(M, symbols))

type KeyGroups<-M: Data> is Data:
  KeyGroups{indices: List<&2, PropertyKey<M>>, strings: List<&2, PropertyKey<M>>}

def groupKey(-M: Data, index: Maybe<&2, Nat>, key: String, groups: KeyGroups<M>) -> KeyGroups<M>:
  match index groups:
    case Some{_} KeyGroups{indices, strings}: KeyGroups{StringKey{key} <> indices, strings}
    case None{} KeyGroups{indices, strings}: KeyGroups{indices, StringKey{key} <> strings}

def groupKeys(-M: Data, properties: List<&2, Record.Property<V.Descriptor<M, V.Value<M>>>>) -> KeyGroups<M>:
  match properties:
    case Nil{}: KeyGroups{Nil{}, Nil{}}
    case Record.Property{+key, _} <> rest: groupKey(M, Record.arrayIndex(key), key, groupKeys(M, rest))

def joinedArrayKeys(-M: Data, groups: KeyGroups<M>, symbols: List<&2, PropertyKey<M>>) -> List<&2, PropertyKey<M>>:
  match groups:
    case KeyGroups{indices, strings}: List.append(&2, PropertyKey<M>, indices, StringKey{"length"} <> List.append(&2, PropertyKey<M>, strings, symbols))

# Array length is created before user properties and is non-enumerable, but
# still appears in ownKeys between indexed properties and other strings.
def arrayKeys(-M: Data, value: V.ArrayStorage(M)) -> List<&2, PropertyKey<M>>:
  match value:
    case V.ArrayState{V.ObjectState{properties, symbols, _, _}, _, _}: joinedArrayKeys(M, groupKeys(M, Record.entries(V.Descriptor<M, V.Value<M>>, properties)), symbolKeys(M, symbols))

def ownKeys(-M: Data, value: V.Value<M>) -> IO(Result<&2, &2, ObjectError, List<&2, PropertyKey<M>>>):
  match value:
    case V.ObjectValue{storage}:
      do IO<Result<&2, &2, ObjectError, List<&2, PropertyKey<M>>>>:
        state : V.ObjectStorage(M) <- Ref.read(V.ObjectStorage(M), storage)
        return Done{objectKeys(M, state)}
    case V.ArrayValue{storage}:
      do IO<Result<&2, &2, ObjectError, List<&2, PropertyKey<M>>>>:
        state : V.ArrayStorage(M) <- Ref.read(V.ArrayStorage(M), storage)
        return Done{arrayKeys(M, state)}
    case V.Callable{_}: IO.pure(Result<&2, &2, ObjectError, List<&2, PropertyKey<M>>>, Fail{UnsupportedCallableObject{}})
    case _: IO.pure(Result<&2, &2, ObjectError, List<&2, PropertyKey<M>>>, Fail{NotObject{}})

def symbolDescriptor(~M: Data, ~same: M -> M -> Bool, symbols: List<&2, V.SymbolProperty<M, V.Value<M>>>, +key: M) -> Maybe<&2, V.Descriptor<M, V.Value<M>>>:
  match symbols:
    case Nil{}: None{}
    case V.SymbolProperty{identity, descriptor} <> rest: Bool.pick(Maybe<&2, V.Descriptor<M, V.Value<M>>>, same(identity, key), Some{descriptor}, symbolDescriptor(~M, ~same, rest, key))

def objectDescriptor(~M: Data, ~same: M -> M -> Bool, value: V.ObjectStorage(M), key: PropertyKey<M>) -> Maybe<&2, V.Descriptor<M, V.Value<M>>>:
  match value key:
    case V.ObjectState{properties, _, _, _} StringKey{name}: Record.get(V.Descriptor<M, V.Value<M>>, properties, name)
    case V.ObjectState{_, symbols, _, _} SymbolKey{identity}: symbolDescriptor(~M, ~same, symbols, identity)

def arrayDescriptor(~M: Data, ~same: M -> M -> Bool, value: V.ArrayStorage(M), key: PropertyKey<M>) -> Maybe<&2, V.Descriptor<M, V.Value<M>>>:
  match value key:
    case V.ArrayState{object, length, writable} StringKey{+name}: Bool.pick(Maybe<&2, V.Descriptor<M, V.Value<M>>>, String.eq(name, "length"), Some{V.DataProperty{V.Number{F.fromU32(length)}, writable, False{}, False{}}}, objectDescriptor(~M, ~same, object, StringKey{name}))
    case V.ArrayState{object, _, _} SymbolKey{identity}: objectDescriptor(~M, ~same, object, SymbolKey{identity})

# Inspection returns descriptors without invoking getters or traversing a
# prototype. The pure metadata comparator supplies symbol identity only.
def getOwnPropertyDescriptor(~M: Data, ~same: M -> M -> Bool, value: V.Value<M>, key: PropertyKey<M>) -> IO(Result<&2, &2, ObjectError, Maybe<&2, V.Descriptor<M, V.Value<M>>>>):
  match value:
    case V.ObjectValue{storage}:
      do IO<Result<&2, &2, ObjectError, Maybe<&2, V.Descriptor<M, V.Value<M>>>>>:
        state : V.ObjectStorage(M) <- Ref.read(V.ObjectStorage(M), storage)
        return Done{objectDescriptor(~M, ~same, state, key)}
    case V.ArrayValue{storage}:
      do IO<Result<&2, &2, ObjectError, Maybe<&2, V.Descriptor<M, V.Value<M>>>>>:
        state : V.ArrayStorage(M) <- Ref.read(V.ArrayStorage(M), storage)
        return Done{arrayDescriptor(~M, ~same, state, key)}
    case V.Callable{_}: IO.pure(Result<&2, &2, ObjectError, Maybe<&2, V.Descriptor<M, V.Value<M>>>>, Fail{UnsupportedCallableObject{}})
    case _: IO.pure(Result<&2, &2, ObjectError, Maybe<&2, V.Descriptor<M, V.Value<M>>>>, Fail{NotObject{}})
