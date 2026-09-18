import Base
import ./utf16.bend as U

# Own enumerable string properties, with JavaScript object enumeration order:
# canonical array-index keys first numerically, then other keys by insertion.
# This is not a prototype chain or a replacement for Map's insertion ordering.
type Property<-V: Data> is Data:
  Property{key: String, value: V}

type Record<-V: Data> is Data:
  Record{properties: List<&2, Property<V>>}

def scanIndex(chars: String, accumulator: Nat, valid: Bool) -> Maybe<&2, Nat>:
  match chars:
    case SNil{}: Bool.pick(Maybe<&2, Nat>, valid, Some{accumulator}, None{})
    case SCon{Chr{+code}, rest}:
      +next = (accumulator * 10n + U32.to_nat((code - 48 : U32)) : Nat)
      +accepted = (valid && U32.is_ge(code, 48) && U32.is_le(code, 57) && Nat.is_le(next, U32.to_nat(4294967294)) : Bool)
      scanIndex(rest, Bool.pick(Nat, accepted, next, 0n), accepted)

def arrayIndex(key: String) -> Maybe<&2, Nat>:
  match key:
    case SNil{}: None{}
    case SCon{Chr{48}, SNil{}}: Some{0n}
    case SCon{Chr{48}, _}: None{}
    case key: scanIndex(key, 0n, True{})

def indexBefore(left: Maybe<&2, Nat>, right: Maybe<&2, Nat>) -> Bool:
  match left right:
    case Some{a} Some{b}: Nat.is_lt(a, b)
    case Some{_} None{}: True{}
    case _ _: False{}

def new(-V: Data) -> Record<V>: Record{Nil{}}

def getProperties(-V: Data, properties: List<&2, Property<V>>, +key: String) -> Maybe<&2, V>:
  match properties:
    case Nil{}: None{}
    case Property{name, value} <> rest:
      Bool.pick(Maybe<&2, V>, String.eq(name, key), Some{value}, getProperties(V, rest, key))

def get(-V: Data, record: Record<V>, key: String) -> Maybe<&2, V>:
  match record:
    case Record{properties}: getProperties(V, properties, U.normalize(key))

# Pure recursive insertion preserves position on replacement and moves a
# deleted/re-added non-index key to the end, matching ordinary object keys.
def setProperties(-V: Data, properties: List<&2, Property<V>>, +key: String, +value: V) -> List<&2, Property<V>>:
  match properties:
    case Nil{}: Property{key, value} <> Nil{}
    case Property{+name, +old} <> +rest:
      Bool.pick(List<&2, Property<V>>, String.eq(key, name), Property{key, value} <> rest,
        Bool.pick(List<&2, Property<V>>, indexBefore(arrayIndex(key), arrayIndex(name)), Property{key, value} <> Property{name, old} <> rest, Property{name, old} <> setProperties(V, rest, key, value)))

def set(-V: Data, record: Record<V>, key: String, value: V) -> Record<V>:
  match record:
    case Record{properties}: Record{setProperties(V, properties, U.normalize(key), value)}

def removeProperties(-V: Data, properties: List<&2, Property<V>>, +key: String) -> List<&2, Property<V>>:
  match properties:
    case Nil{}: Nil{}
    case Property{+name, value} <> rest:
      +tail = removeProperties(V, rest, key)
      Bool.pick(List<&2, Property<V>>, String.eq(name, key), tail, Property{name, value} <> tail)

def remove(-V: Data, record: Record<V>, key: String) -> Record<V>:
  match record:
    case Record{properties}: Record{removeProperties(V, properties, U.normalize(key))}

def entries(-V: Data, record: Record<V>) -> List<&2, Property<V>>:
  match record:
    case Record{properties}: properties
