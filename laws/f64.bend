import Base
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/u64.bend as W

# Comparison outcomes and finiteness of decoded binary64 values.

law finite_values_are_finite:
  for negative: Bool
  for exponent: U32
  for significand: W.U64
  {F.isFinite(F.Finite{negative, exponent, significand}) == True{} : Bool}

law infinities_are_not_finite:
  for negative: Bool
  {F.isFinite(F.Infinity{negative}) == False{} : Bool}

law nan_is_not_finite:
  {F.isFinite(F.NotANumber{}) == False{} : Bool}

law at_least_is_equal_or_greater:
  for order: Maybe<&2, Cmp>
  {F.isAtLeast(order) == Bool.or(F.isEqual(order), F.isGreater(order)) : Bool}

law at_most_excludes_greater_and_unordered:
  for order: Maybe<&2, Cmp>
  {F.isAtMost(order) == Bool.and(Maybe.is_some(&2, Cmp, order), Bool.not(F.isGreater(order))) : Bool}

law unordered_comparisons_satisfy_nothing:
  {Bool.or(Bool.or(F.isEqual(None{}), F.isGreater(None{})), Bool.or(F.isAtLeast(None{}), F.isAtMost(None{}))) == False{} : Bool}

law minimum_of_unordered_is_nan:
  for value: F.F64
  {F.minimum(F.nan(), value) == F.nan() : F.F64}

law maximum_of_unordered_is_nan:
  for value: F.F64
  {F.maximum(F.nan(), value) == F.nan() : F.F64}
