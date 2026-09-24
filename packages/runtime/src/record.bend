import Base

# Persistent string-keyed dictionary. Entries retain insertion order; replacing
# a value keeps its position. Numeric-looking keys are ordinary strings.
type Property<-V: Data> is Data:
  Property{key: String, value: V}

type Record<-V: Data> is Data:
  Record{properties: List<&2, Property<V>>}

def new(-V: Data) -> Record<V>: Record{Nil{}}

# Lookups stop at the first match: `found` carries the previous entry's value
# when its key matched, so the scan branches on a parameter.
def getFrom(-V: Data, properties: List<&2, Property<V>>, found: Maybe<&2, V>, +key: String) -> Maybe<&2, V>:
  match properties found:
    case _ Some{value}: Some{value}
    case Nil{} None{}: None{}
    case Property{name, value} <> rest None{}:
      getFrom(V, rest, Bool.pick(Maybe<&2, V>, String.eq(name, key), Some{value}, None{}), key)

def getProperties(-V: Data, properties: List<&2, Property<V>>, key: String) -> Maybe<&2, V>:
  getFrom(V, properties, None{}, key)

def get(-V: Data, record: Record<V>, key: String) -> Maybe<&2, V>:
  match record:
    case Record{properties}: getProperties(V, properties, key)

# Pure updates leave prior dictionaries unchanged.
def keyAt(-V: Data, properties: List<&2, Property<V>>, key: String) -> Bool:
  match properties:
    case Nil{}: False{}
    case Property{name, _} <> _: String.eq(key, name)

# `same` says whether the first entry has the key; the suffix after a
# replaced entry is kept as it is.
def setFrom(-V: Data, properties: List<&2, Property<V>>, same: Bool, +key: String, +value: V) -> List<&2, Property<V>>:
  match properties same:
    case Nil{} _: Property{key, value} <> Nil{}
    case _ <> rest True{}: Property{key, value} <> rest
    case Property{name, old} <> +rest False{}: Property{name, old} <> setFrom(V, rest, keyAt(V, rest, key), key, value)

def setProperties(-V: Data, +properties: List<&2, Property<V>>, +key: String, value: V) -> List<&2, Property<V>>:
  setFrom(V, properties, keyAt(V, properties, key), key, value)

def set(-V: Data, record: Record<V>, key: String, value: V) -> Record<V>:
  match record:
    case Record{properties}: Record{setProperties(V, properties, key, value)}

def removeProperties(-V: Data, properties: List<&2, Property<V>>, +key: String) -> List<&2, Property<V>>:
  match properties:
    case Nil{}: Nil{}
    case Property{+name, value} <> rest:
      +tail = removeProperties(V, rest, key)
      Bool.pick(List<&2, Property<V>>, String.eq(name, key), tail, Property{name, value} <> tail)

def remove(-V: Data, record: Record<V>, key: String) -> Record<V>:
  match record:
    case Record{properties}: Record{removeProperties(V, properties, key)}

def entries(-V: Data, record: Record<V>) -> List<&2, Property<V>>:
  match record:
    case Record{properties}: properties
