import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/json-finite.bend as S
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/u64.bend as W
import ../packages/runtime/src/record.bend as R

law finite_components_are_accepted:
  for sign: Bool
  for exponent: U32
  for significand: W.U64
  {S.number(F.Finite{sign, exponent, significand}) == True{} : Bool}

law infinities_are_rejected:
  for sign: Bool
  {S.number(F.Infinity{sign}) == False{} : Bool}

law array_checks_head_and_tail:
  for head: T.JsonValue
  for tail: List<&2, T.JsonValue>
  {S.valid(T.JsonArray{head <> tail}) == (S.valid(head) && S.valid(T.JsonArray{tail})) : Bool}

law object_checks_value_and_tail:
  for key: String
  for value: T.JsonValue
  for tail: List<&2, R.Property<T.JsonValue>>
  {S.valid(T.JsonObject{R.Record{R.Property{key, value} <> tail}}) == (S.valid(value) && S.valid(T.JsonObject{R.Record{tail}})) : Bool}

law string_contents_are_not_numbers:
  for text: String
  {S.valid(T.JsonString{text}) == True{} : Bool}

law array_partition:
  for +left: List<&2, T.JsonValue>
  for +right: List<&2, T.JsonValue>
  {S.valid(T.JsonArray{List.append(&2, T.JsonValue, left, right)}) == (S.valid(T.JsonArray{left}) && S.valid(T.JsonArray{right})) : Bool}

law invalid_numeric_leaf_is_rejected:
  for +value: F.F64
  for invalid: {S.number(F.decode(value)) == False{} : Bool}
  {S.valid(T.JsonNumber{value}) == False{} : Bool}
