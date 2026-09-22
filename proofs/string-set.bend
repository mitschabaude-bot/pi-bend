import Base
import ./record.bend as RecordProof
import ../laws/record.bend as RecordLaws
import ../laws/string-set.bend as Laws
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/string.bend as Set

def Laws.empty_membership(value): {==}

def Laws.remove_membership(values, value):
  match values:
    case Set.StringSet{entries}:
      Equal.cong(Maybe<&2, Unit>, Bool, result => Bool.not(Maybe.is_none(&2, Unit, result)), R.get(Unit, R.remove(Unit, entries, value), value), None{}, RecordLaws.remove_absent(Unit, entries, value))

def Laws.remove_idempotent(values, value):
  match values:
    case Set.StringSet{entries}:
      Equal.cong(R.Record<Unit>, Set.StringSet, record => Set.StringSet{record}, R.remove(Unit, R.remove(Unit, entries, value), value), R.remove(Unit, entries, value), RecordLaws.remove_idempotent(Unit, entries, value))

def Laws.insert_membership(values, value):
  match values:
    case Set.StringSet{entries}:
      Equal.cong(Maybe<&2, Unit>, Bool, result => Bool.not(Maybe.is_none(&2, Unit, result)), R.get(Unit, R.set(Unit, entries, value, Unit{}), value), Some{Unit{}}, RecordLaws.lookup_after_set(Unit, entries, value, Unit{}))

def Laws.insert_idempotent(values, value):
  match values:
    case Set.StringSet{entries}:
      Equal.cong(R.Record<Unit>, Set.StringSet, record => Set.StringSet{record}, R.set(Unit, R.set(Unit, entries, value, Unit{}), value, Unit{}), R.set(Unit, entries, value, Unit{}), RecordLaws.set_overwrite(Unit, entries, value, Unit{}, Unit{}))

def Laws.remove_after_insert(values, value):
  match values:
    case Set.StringSet{entries}:
      Equal.cong(R.Record<Unit>, Set.StringSet, record => Set.StringSet{record}, R.remove(Unit, R.set(Unit, entries, value, Unit{}), value), R.remove(Unit, entries, value), RecordLaws.remove_after_set(Unit, entries, value, Unit{}))
