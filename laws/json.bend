import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/json.bend as S
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/u64.bend as W
import ../packages/runtime/src/record.bend as R

law finite_components_are_accepted:
  for sign: Bool
  for exponent: U32
  for significand: W.U64
  {S.finiteNumber(F.Finite{sign, exponent, significand}) == True{} : Bool}

law infinities_are_rejected:
  for sign: Bool
  {S.finiteNumber(F.Infinity{sign}) == False{} : Bool}

law array_checks_head_and_tail:
  for head: T.JsonValue
  for tail: List<&2, T.JsonValue>
  {S.finite(T.JsonArray{head <> tail}) == (S.finite(head) && S.finite(T.JsonArray{tail})) : Bool}

law object_checks_value_and_tail:
  for key: String
  for value: T.JsonValue
  for tail: List<&2, R.Property<T.JsonValue>>
  {S.finite(T.JsonObject{R.Record{R.Property{key, value} <> tail}}) == (S.finite(value) && S.finite(T.JsonObject{R.Record{tail}})) : Bool}

law string_contents_are_not_numbers:
  for text: String
  {S.finite(T.JsonString{text}) == True{} : Bool}

law array_partition:
  for +left: List<&2, T.JsonValue>
  for +right: List<&2, T.JsonValue>
  {S.finite(T.JsonArray{List.append(&2, T.JsonValue, left, right)}) == (S.finite(T.JsonArray{left}) && S.finite(T.JsonArray{right})) : Bool}

law invalid_numeric_leaf_is_rejected:
  for +value: F.F64
  for invalid: {S.finiteNumber(F.decode(value)) == False{} : Bool}
  {S.finite(T.JsonNumber{value}) == False{} : Bool}
