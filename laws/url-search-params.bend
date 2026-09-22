import Base
import ../packages/runtime/src/url.bend as P
import ../packages/runtime/src/url.bend as F

# Ordered tuples, not object properties: duplicates and position are data.
law names_partition:
  for +left: List<&2, F.Entry>
  for +right: List<&2, F.Entry>
  {P.names(List.append(&2, F.Entry, left, right)) == List.append(&2, String, P.names(left), P.names(right)) : List<&2, String>}

law values_partition:
  for +left: List<&2, F.Entry>
  for +right: List<&2, F.Entry>
  {P.contents(List.append(&2, F.Entry, left, right)) == List.append(&2, String, P.contents(left), P.contents(right)) : List<&2, String>}

law normalization_partition:
  for +left: List<&2, F.Entry>
  for +right: List<&2, F.Entry>
  {P.normalizedSearchParams(List.append(&2, F.Entry, left, right)) == List.append(&2, F.Entry, P.normalizedSearchParams(left), P.normalizedSearchParams(right)) : List<&2, F.Entry>}

law names_retain_head:
  for name: String
  for value: String
  for rest: List<&2, F.Entry>
  {P.names(F.Entry{name, value} <> rest) == name <> P.names(rest) : List<&2, String>}

law values_retain_head:
  for name: String
  for value: String
  for rest: List<&2, F.Entry>
  {P.contents(F.Entry{name, value} <> rest) == value <> P.contents(rest) : List<&2, String>}

law append_preserves_prefix:
  for +params: P.URLSearchParams
  for +name: String
  for +value: String
  {P.entries(P.append(params, name, value)) == List.append(&2, F.Entry, P.entries(params), F.normalize(F.Entry{name, value}) <> Nil{}) : List<&2, F.Entry>}

law remove_matching_head:
  for +entry: F.Entry
  for rest: List<&2, F.Entry>
  for +name: String
  for +value: Maybe<&2, String>
  for matches: {P.matches(entry, name, value) == True{} : Bool}
  {P.remove(entry <> rest, name, value) == P.remove(rest, name, value) : List<&2, F.Entry>}

law remove_preserves_other_head:
  for +entry: F.Entry
  for rest: List<&2, F.Entry>
  for +name: String
  for +value: Maybe<&2, String>
  for different: {P.matches(entry, name, value) == False{} : Bool}
  {P.remove(entry <> rest, name, value) == entry <> P.remove(rest, name, value) : List<&2, F.Entry>}

law empty_lookup:
  for name: String
  {P.get(P.new(), name) == None{} : Maybe<&2, String>}

law remove_idempotent:
  for +entries: List<&2, F.Entry>
  for +name: String
  for +value: Maybe<&2, String>
  {P.remove(P.remove(entries, name, value), name, value) == P.remove(entries, name, value) : List<&2, F.Entry>}
