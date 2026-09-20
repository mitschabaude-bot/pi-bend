import Base
import ../packages/runtime/src/string-set.bend as Set

law empty_membership:
  for value: String
  {Set.contains(Set.empty(), value) == False{} : Bool}

law remove_membership:
  for values: Set.Set
  for +value: String
  {Set.contains(Set.remove(values, value), value) == False{} : Bool}

law remove_idempotent:
  for +values: Set.Set
  for +value: String
  {Set.remove(Set.remove(values, value), value) == Set.remove(values, value) : Set.Set}
