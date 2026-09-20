import Base
import ./string-equality.bend as StringEquality
import ../laws/record.bend as Laws
import ../packages/runtime/src/record.bend as R

law remove_properties_absent:
  for -A: Data
  for properties: List<&2, R.Property<A>>
  for +key: String
  {R.getProperties(A, R.removeProperties(A, properties, key), key) == None{} : Maybe<&2, A>}

law filtered_head_absent:
  for -A: Data
  for +name: String
  for value: A
  for +rest: List<&2, R.Property<A>>
  for +key: String
  for +same: Bool
  for equal: {same == String.eq(name, key) : Bool}
  for absent: {R.getProperties(A, rest, key) == None{} : Maybe<&2, A>}
  {R.getProperties(A, Bool.pick(List<&2, R.Property<A>>, same, rest, R.Property{name, value} <> rest), key) == None{} : Maybe<&2, A>}

def filtered_head_absent(A, name, value, rest, key, same, equal, absent):
  match same:
    case True{}: absent
    case False{}:
      %equal : {Bool.pick(Maybe<&2, A>, _, Some{value}, R.getProperties(A, rest, key)) == None{} : Maybe<&2, A>}
      absent

def remove_properties_absent(A, properties, key):
  match properties:
    case Nil{}: {==}
    case R.Property{+name, value} <> +rest:
      filtered_head_absent(A, name, value, R.removeProperties(A, rest, key), key, String.eq(name, key), {==}, remove_properties_absent(A, rest, key))

def Laws.remove_absent(A, record, key):
  match record:
    case R.Record{properties}: remove_properties_absent(A, properties, key)

def Laws.empty_lookup(A, key): {==}

law filtered_head_twice:
  for -A: Data
  for +name: String
  for +value: A
  for +rest: List<&2, R.Property<A>>
  for +key: String
  for +same: Bool
  for equal: {same == String.eq(name, key) : Bool}
  for unchanged: {R.removeProperties(A, rest, key) == rest : List<&2, R.Property<A>>}
  {R.removeProperties(A, Bool.pick(List<&2, R.Property<A>>, same, rest, R.Property{name, value} <> rest), key) == Bool.pick(List<&2, R.Property<A>>, same, rest, R.Property{name, value} <> rest) : List<&2, R.Property<A>>}

def filtered_head_twice(A, name, value, rest, key, same, equal, unchanged):
  match same:
    case True{}: unchanged
    case False{}:
      %equal : {Bool.pick(List<&2, R.Property<A>>, _, R.removeProperties(A, rest, key), R.Property{name, value} <> R.removeProperties(A, rest, key)) == R.Property{name, value} <> rest : List<&2, R.Property<A>>}
      Equal.cong(List<&2, R.Property<A>>, List<&2, R.Property<A>>, tail => R.Property{name, value} <> tail, R.removeProperties(A, rest, key), rest, unchanged)

law remove_properties_twice:
  for -A: Data
  for +properties: List<&2, R.Property<A>>
  for +key: String
  {R.removeProperties(A, R.removeProperties(A, properties, key), key) == R.removeProperties(A, properties, key) : List<&2, R.Property<A>>}

def remove_properties_twice(A, properties, key):
  match properties:
    case Nil{}: {==}
    case R.Property{+name, +value} <> +rest:
      filtered_head_twice(A, name, value, R.removeProperties(A, rest, key), key, String.eq(name, key), {==}, remove_properties_twice(A, rest, key))

def Laws.remove_idempotent(A, record, key):
  match record:
    case R.Record{properties}:
      Equal.cong(List<&2, R.Property<A>>, R.Record<A>, items => R.Record{items}, R.removeProperties(A, R.removeProperties(A, properties, key), key), R.removeProperties(A, properties, key), remove_properties_twice(A, properties, key))

def Laws.remove_preserves_other_head(A, name, value, rest, key, different):
  %different : {R.Record{Bool.pick(List<&2, R.Property<A>>, _, R.removeProperties(A, rest, key), R.Property{name, value} <> R.removeProperties(A, rest, key))} == R.Record{R.Property{name, value} <> R.removeProperties(A, rest, key)} : R.Record<A>}
  {==}

law set_head_lookup:
  for -A: Data
  for +name: String
  for +old: A
  for +rest: List<&2, R.Property<A>>
  for +key: String
  for +value: A
  for +same: Bool
  for equal: {same == String.eq(key, name) : Bool}
  for found: {R.getProperties(A, R.setProperties(A, rest, key, value), key) == Some{value} : Maybe<&2, A>}
  {R.getProperties(A, Bool.pick(List<&2, R.Property<A>>, same, R.Property{key, value} <> rest, R.Property{name, old} <> R.setProperties(A, rest, key, value)), key) == Some{value} : Maybe<&2, A>}

def set_head_lookup(A, name, old, rest, key, value, same, equal, found):
  match same:
    case True{}:
      %StringEquality.eq_reflexive(key) : {Bool.pick(Maybe<&2, A>, _, Some{value}, R.getProperties(A, rest, key)) == Some{value} : Maybe<&2, A>}
      {==}
    case False{}:
      %StringEquality.eq_symmetric(key, name) : {Bool.pick(Maybe<&2, A>, _, Some{old}, R.getProperties(A, R.setProperties(A, rest, key, value), key)) == Some{value} : Maybe<&2, A>}
      %equal : {Bool.pick(Maybe<&2, A>, _, Some{old}, R.getProperties(A, R.setProperties(A, rest, key, value), key)) == Some{value} : Maybe<&2, A>}
      found

law set_properties_lookup:
  for -A: Data
  for properties: List<&2, R.Property<A>>
  for +key: String
  for +value: A
  {R.getProperties(A, R.setProperties(A, properties, key, value), key) == Some{value} : Maybe<&2, A>}

def set_properties_lookup(A, properties, key, value):
  match properties:
    case Nil{}:
      %StringEquality.eq_reflexive(key) : {Bool.pick(Maybe<&2, A>, _, Some{value}, None{}) == Some{value} : Maybe<&2, A>}
      {==}
    case R.Property{+name, old} <> +rest:
      set_head_lookup(A, name, old, rest, key, value, String.eq(key, name), {==}, set_properties_lookup(A, rest, key, value))

def Laws.lookup_after_set(A, record, key, value):
  match record:
    case R.Record{properties}: set_properties_lookup(A, properties, key, value)

law set_head_overwrite:
  for -A: Data
  for +name: String
  for +old: A
  for +rest: List<&2, R.Property<A>>
  for +key: String
  for +first: A
  for +last: A
  for +same: Bool
  for equal: {same == String.eq(key, name) : Bool}
  for tail: {R.setProperties(A, R.setProperties(A, rest, key, first), key, last) == R.setProperties(A, rest, key, last) : List<&2, R.Property<A>>}
  {R.setProperties(A, Bool.pick(List<&2, R.Property<A>>, same, R.Property{key, first} <> rest, R.Property{name, old} <> R.setProperties(A, rest, key, first)), key, last) == Bool.pick(List<&2, R.Property<A>>, same, R.Property{key, last} <> rest, R.Property{name, old} <> R.setProperties(A, rest, key, last)) : List<&2, R.Property<A>>}

def set_head_overwrite(A, name, old, rest, key, first, last, same, equal, tail):
  match same:
    case True{}:
      %StringEquality.eq_reflexive(key) : {Bool.pick(List<&2, R.Property<A>>, _, R.Property{key, last} <> rest, R.Property{key, first} <> R.setProperties(A, rest, key, last)) == R.Property{key, last} <> rest : List<&2, R.Property<A>>}
      {==}
    case False{}:
      %equal : {Bool.pick(List<&2, R.Property<A>>, _, R.Property{key, last} <> R.setProperties(A, rest, key, first), R.Property{name, old} <> R.setProperties(A, R.setProperties(A, rest, key, first), key, last)) == R.Property{name, old} <> R.setProperties(A, rest, key, last) : List<&2, R.Property<A>>}
      Equal.cong(List<&2, R.Property<A>>, List<&2, R.Property<A>>, items => R.Property{name, old} <> items, R.setProperties(A, R.setProperties(A, rest, key, first), key, last), R.setProperties(A, rest, key, last), tail)

law set_properties_overwrite:
  for -A: Data
  for +properties: List<&2, R.Property<A>>
  for +key: String
  for +first: A
  for +last: A
  {R.setProperties(A, R.setProperties(A, properties, key, first), key, last) == R.setProperties(A, properties, key, last) : List<&2, R.Property<A>>}

def set_properties_overwrite(A, properties, key, first, last):
  match properties:
    case Nil{}:
      %StringEquality.eq_reflexive(key) : {Bool.pick(List<&2, R.Property<A>>, _, R.Property{key, last} <> Nil{}, R.Property{key, first} <> (R.Property{key, last} <> Nil{})) == R.Property{key, last} <> Nil{} : List<&2, R.Property<A>>}
      {==}
    case R.Property{+name, +old} <> +rest:
      set_head_overwrite(A, name, old, rest, key, first, last, String.eq(key, name), {==}, set_properties_overwrite(A, rest, key, first, last))

def Laws.set_overwrite(A, record, key, first, last):
  match record:
    case R.Record{properties}:
      Equal.cong(List<&2, R.Property<A>>, R.Record<A>, items => R.Record{items}, R.setProperties(A, R.setProperties(A, properties, key, first), key, last), R.setProperties(A, properties, key, last), set_properties_overwrite(A, properties, key, first, last))

law set_head_remove:
  for -A: Data
  for +name: String
  for +old: A
  for +rest: List<&2, R.Property<A>>
  for +key: String
  for +value: A
  for +same: Bool
  for equal: {same == String.eq(key, name) : Bool}
  for tail: {R.removeProperties(A, R.setProperties(A, rest, key, value), key) == R.removeProperties(A, rest, key) : List<&2, R.Property<A>>}
  {R.removeProperties(A, Bool.pick(List<&2, R.Property<A>>, same, R.Property{key, value} <> rest, R.Property{name, old} <> R.setProperties(A, rest, key, value)), key) == Bool.pick(List<&2, R.Property<A>>, same, R.removeProperties(A, rest, key), R.Property{name, old} <> R.removeProperties(A, rest, key)) : List<&2, R.Property<A>>}

def set_head_remove(A, name, old, rest, key, value, same, equal, tail):
  match same:
    case True{}:
      %StringEquality.eq_reflexive(key) : {Bool.pick(List<&2, R.Property<A>>, _, R.removeProperties(A, rest, key), R.Property{key, value} <> R.removeProperties(A, rest, key)) == R.removeProperties(A, rest, key) : List<&2, R.Property<A>>}
      {==}
    case False{}:
      %StringEquality.eq_symmetric(key, name) : {Bool.pick(List<&2, R.Property<A>>, _, R.removeProperties(A, R.setProperties(A, rest, key, value), key), R.Property{name, old} <> R.removeProperties(A, R.setProperties(A, rest, key, value), key)) == R.Property{name, old} <> R.removeProperties(A, rest, key) : List<&2, R.Property<A>>}
      %equal : {Bool.pick(List<&2, R.Property<A>>, _, R.removeProperties(A, R.setProperties(A, rest, key, value), key), R.Property{name, old} <> R.removeProperties(A, R.setProperties(A, rest, key, value), key)) == R.Property{name, old} <> R.removeProperties(A, rest, key) : List<&2, R.Property<A>>}
      Equal.cong(List<&2, R.Property<A>>, List<&2, R.Property<A>>, items => R.Property{name, old} <> items, R.removeProperties(A, R.setProperties(A, rest, key, value), key), R.removeProperties(A, rest, key), tail)

law set_properties_remove:
  for -A: Data
  for +properties: List<&2, R.Property<A>>
  for +key: String
  for +value: A
  {R.removeProperties(A, R.setProperties(A, properties, key, value), key) == R.removeProperties(A, properties, key) : List<&2, R.Property<A>>}

def set_properties_remove(A, properties, key, value):
  match properties:
    case Nil{}:
      %StringEquality.eq_reflexive(key) : {Bool.pick(List<&2, R.Property<A>>, _, Nil{}, R.Property{key, value} <> Nil{}) == Nil{} : List<&2, R.Property<A>>}
      {==}
    case R.Property{+name, +old} <> +rest:
      %StringEquality.eq_symmetric(key, name) : {R.removeProperties(A, R.setProperties(A, R.Property{name, old} <> rest, key, value), key) == Bool.pick(List<&2, R.Property<A>>, _, R.removeProperties(A, rest, key), R.Property{name, old} <> R.removeProperties(A, rest, key)) : List<&2, R.Property<A>>}
      set_head_remove(A, name, old, rest, key, value, String.eq(key, name), {==}, set_properties_remove(A, rest, key, value))

def Laws.remove_after_set(A, record, key, value):
  match record:
    case R.Record{properties}:
      Equal.cong(List<&2, R.Property<A>>, R.Record<A>, items => R.Record{items}, R.removeProperties(A, R.setProperties(A, properties, key, value), key), R.removeProperties(A, properties, key), set_properties_remove(A, properties, key, value))
