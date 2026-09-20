import Base
import ../packages/runtime/src/record.bend as R

law remove_absent:
  for -A: Data
  for record: R.Record<A>
  for +key: String
  {R.get(A, R.remove(A, record, key), key) == None{} : Maybe<&2, A>}

law empty_lookup:
  for -A: Data
  for key: String
  {R.get(A, R.new(A), key) == None{} : Maybe<&2, A>}

law remove_idempotent:
  for -A: Data
  for +record: R.Record<A>
  for +key: String
  {R.remove(A, R.remove(A, record, key), key) == R.remove(A, record, key) : R.Record<A>}

# Deletion retains every nonmatching entry in place, with its original value.
law remove_preserves_other_head:
  for -A: Data
  for +name: String
  for +value: A
  for +rest: List<&2, R.Property<A>>
  for +key: String
  for different: {False{} == String.eq(name, key) : Bool}
  {R.remove(A, R.Record{R.Property{name, value} <> rest}, key) == R.Record{R.Property{name, value} <> R.removeProperties(A, rest, key)} : R.Record<A>}

law lookup_after_set:
  for -A: Data
  for record: R.Record<A>
  for +key: String
  for +value: A
  {R.get(A, R.set(A, record, key, value), key) == Some{value} : Maybe<&2, A>}
