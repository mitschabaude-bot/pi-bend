import Base

# Persistent string-keyed dictionary. Entries retain insertion order; replacing
# a value keeps its position. Numeric-looking keys are ordinary strings.
type Property<-V: Data> is Data:
  Property{key: String, value: V}

type Record<-V: Data> is Data:
  Record{properties: List<&2, Property<V>>}

def new(-V: Data) -> Record<V>: Record{Nil{}}

def getProperties(-V: Data, properties: List<&2, Property<V>>, +key: String) -> Maybe<&2, V>:
  match properties:
    case Nil{}: None{}
    case Property{name, value} <> rest:
      Bool.pick(Maybe<&2, V>, String.eq(name, key), Some{value}, getProperties(V, rest, key))

def get(-V: Data, record: Record<V>, key: String) -> Maybe<&2, V>:
  match record:
    case Record{properties}: getProperties(V, properties, key)

# Pure updates leave prior dictionaries unchanged.
def setProperties(-V: Data, properties: List<&2, Property<V>>, +key: String, +value: V) -> List<&2, Property<V>>:
  match properties:
    case Nil{}: Property{key, value} <> Nil{}
    case Property{+name, +old} <> +rest:
      Bool.pick(List<&2, Property<V>>, String.eq(key, name), Property{key, value} <> rest,
        Property{name, old} <> setProperties(V, rest, key, value))

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
