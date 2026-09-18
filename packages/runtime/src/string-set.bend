import Base
import ./record.bend as R

# An immutable set of string identifiers. Insertion preserves existing members.
type Set is Data:
  Set{entries: R.Record<Unit>}

def empty() -> Set: Set{R.new(Unit)}
def contains(values: Set, value: String) -> Bool:
  match values:
    case Set{entries}: Bool.not(Maybe.is_none(&2, Unit, R.get(Unit, entries, value)))
def insert(values: Set, value: String) -> Set:
  match values:
    case Set{entries}: Set{R.set(Unit, entries, value, Unit{})}
def remove(values: Set, value: String) -> Set:
  match values:
    case Set{entries}: Set{R.remove(Unit, entries, value)}
def keys(entries: List<&2, R.Property<Unit>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, _} <> rest: key <> keys(rest)
def toList(values: Set) -> List<&2, String>:
  match values:
    case Set{entries}: keys(R.entries(Unit, entries))
