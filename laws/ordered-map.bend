import Base
import ../packages/runtime/src/ordered-map.bend as Map
import ../packages/runtime/src/record.bend as Record

# Compare complete entry sequences, retaining key/value pairs and their order.
def dictionary(-A: Data, map: Map.OrderedMap<A>) -> Record.Record<A>:
  Record.Record{Map.entries(A, map)}

law empty:
  for -A: Data
  {dictionary(A, Map.new(A)) == Record.new(A) : Record.Record<A>}

law lookup:
  for -A: Data
  for +map: Map.OrderedMap<A>
  for +key: String
  {Map.get(A, map, key) == Record.get(A, dictionary(A, map), key) : Maybe<&2, A>}

law set:
  for -A: Data
  for +map: Map.OrderedMap<A>
  for +key: String
  for +value: A
  {dictionary(A, Map.set(A, map, key, value)) == Record.set(A, dictionary(A, map), key, value) : Record.Record<A>}

law remove:
  for -A: Data
  for +map: Map.OrderedMap<A>
  for +key: String
  {dictionary(A, Map.remove(A, map, key)) == Record.remove(A, dictionary(A, map), key) : Record.Record<A>}

# The same public-operation history interpreted by each collection API.
type Edit<-A: Data> is Data:
  Write{key: String, value: A}
  Delete{key: String}

def applyMap(-A: Data, edits: List<&2, Edit<A>>, map: Map.OrderedMap<A>) -> Map.OrderedMap<A>:
  match edits:
    case Nil{}: map
    case Write{key, value} <> rest: applyMap(A, rest, Map.set(A, map, key, value))
    case Delete{key} <> rest: applyMap(A, rest, Map.remove(A, map, key))

def applyRecord(-A: Data, edits: List<&2, Edit<A>>, record: Record.Record<A>) -> Record.Record<A>:
  match edits:
    case Nil{}: record
    case Write{key, value} <> rest: applyRecord(A, rest, Record.set(A, record, key, value))
    case Delete{key} <> rest: applyRecord(A, rest, Record.remove(A, record, key))

law edit_sequence:
  for -A: Data
  for +edits: List<&2, Edit<A>>
  for +map: Map.OrderedMap<A>
  {dictionary(A, applyMap(A, edits, map)) == applyRecord(A, edits, dictionary(A, map)) : Record.Record<A>}
