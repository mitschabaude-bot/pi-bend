import Base
import ../packages/runtime/src/string.bend as Set

law empty_membership:
  for value: String
  {Set.contains(Set.empty(), value) == False{} : Bool}

law remove_membership:
  for values: Set.StringSet
  for +value: String
  {Set.contains(Set.remove(values, value), value) == False{} : Bool}

law remove_idempotent:
  for +values: Set.StringSet
  for +value: String
  {Set.remove(Set.remove(values, value), value) == Set.remove(values, value) : Set.StringSet}

law insert_membership:
  for values: Set.StringSet
  for +value: String
  {Set.contains(Set.insert(values, value), value) == True{} : Bool}

law insert_idempotent:
  for +values: Set.StringSet
  for +value: String
  {Set.insert(Set.insert(values, value), value) == Set.insert(values, value) : Set.StringSet}

law remove_after_insert:
  for +values: Set.StringSet
  for +value: String
  {Set.remove(Set.insert(values, value), value) == Set.remove(values, value) : Set.StringSet}
