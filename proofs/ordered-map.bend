import Base
import ./string-equality.bend as StringEquality
import ../laws/ordered-map.bend as Laws
import ../packages/runtime/src/ordered-map.bend as Map
import ../packages/runtime/src/record.bend as Record

law put_equivalent:
  for -A: Data
  for +properties: List<&2, Record.Property<A>>
  for +key: String
  for +value: A
  {Map.put(A, properties, key, value) == Record.setProperties(A, properties, key, value) : List<&2, Record.Property<A>>}

def put_equivalent(A, properties, key, value):
  match properties:
    case Nil{}: {==}
    case Record.Property{+name, +old} <> +rest:
      %StringEquality.eq_symmetric(name, key) : {Map.put(A, Record.Property{name, old} <> rest, key, value) == Bool.pick(List<&2, Record.Property<A>>, _, Record.Property{key, value} <> rest, Record.Property{name, old} <> Record.setProperties(A, rest, key, value)) : List<&2, Record.Property<A>>}
      %put_equivalent(A, rest, key, value) : {Map.put(A, Record.Property{name, old} <> rest, key, value) == Bool.pick(List<&2, Record.Property<A>>, String.eq(name, key), Record.Property{key, value} <> rest, Record.Property{name, old} <> _) : List<&2, Record.Property<A>>}
      {==}

def Laws.empty(A): {==}

def Laws.lookup(A, map, key):
  match map:
    case Map.OrderedMap{_}: {==}

def Laws.set(A, map, key, value):
  match map:
    case Map.OrderedMap{properties}:
      Equal.cong(List<&2, Record.Property<A>>, Record.Record<A>, entries => Record.Record{entries}, Map.put(A, properties, key, value), Record.setProperties(A, properties, key, value), put_equivalent(A, properties, key, value))

def Laws.remove(A, map, key):
  match map:
    case Map.OrderedMap{_}: {==}

def Laws.edit_sequence(A, edits, map):
  match edits:
    case Nil{}: {==}
    case Laws.Write{key, value} <> rest:
      %Laws.set(A, map, key, value) : {Laws.dictionary(A, Laws.applyMap(A, rest, Map.set(A, map, key, value))) == Laws.applyRecord(A, rest, _) : Record.Record<A>}
      Laws.edit_sequence(A, rest, Map.set(A, map, key, value))
    case Laws.Delete{key} <> rest:
      %Laws.remove(A, map, key) : {Laws.dictionary(A, Laws.applyMap(A, rest, Map.remove(A, map, key))) == Laws.applyRecord(A, rest, _) : Record.Record<A>}
      Laws.edit_sequence(A, rest, Map.remove(A, map, key))
