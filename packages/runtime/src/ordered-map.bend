import Base
import ./utf16.bend as U
import ./record.bend as R

# String-keyed Map ordering differs from object property enumeration: numeric
# keys retain insertion order too. Replacement keeps position; reinsertion moves.
type OrderedMap<-V: Data> is Data:
  OrderedMap{properties: List<&2, R.Property<V>>}

def new(-V: Data) -> OrderedMap<V>: OrderedMap{Nil{}}

def get(-V: Data, map: OrderedMap<V>, key: String) -> Maybe<&2, V>:
  match map:
    case OrderedMap{properties}: R.getProperties(V, properties, U.normalize(key))

def put(-V: Data, properties: List<&2, R.Property<V>>, +key: String, +value: V) -> List<&2, R.Property<V>>:
  match properties:
    case Nil{}: R.Property{key, value} <> Nil{}
    case R.Property{+name, old} <> +rest:
      Bool.pick(List<&2, R.Property<V>>, String.eq(name, key), R.Property{key, value} <> rest, R.Property{name, old} <> put(V, rest, key, value))

def set(-V: Data, map: OrderedMap<V>, key: String, value: V) -> OrderedMap<V>:
  match map:
    case OrderedMap{properties}: OrderedMap{put(V, properties, U.normalize(key), value)}

def remove(-V: Data, map: OrderedMap<V>, key: String) -> OrderedMap<V>:
  match map:
    case OrderedMap{properties}: OrderedMap{R.removeProperties(V, properties, U.normalize(key))}

def propertyValues(-V: Data, properties: List<&2, R.Property<V>>) -> List<&2, V>:
  match properties:
    case Nil{}: Nil{}
    case R.Property{_, value} <> rest: value <> propertyValues(V, rest)

def values(-V: Data, map: OrderedMap<V>) -> List<&2, V>:
  match map:
    case OrderedMap{properties}: propertyValues(V, properties)

def entries(-V: Data, map: OrderedMap<V>) -> List<&2, R.Property<V>>:
  match map:
    case OrderedMap{properties}: properties
