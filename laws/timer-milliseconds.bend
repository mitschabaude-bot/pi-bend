import Base
import ../packages/runtime/src/timer.bend as T
import ../packages/runtime/src/f64.bend as F

def equalComparison(value: Maybe<&2, Cmp>) -> Bool:
  match value:
    case Some{EQ{}}: True{}
    case _: False{}

def exactResult(value: F.F64, result: Result<&2, &2, T.MillisecondsError, U32>) -> Bool:
  match result:
    case Fail{_}: True{}
    case Done{word}: equalComparison(F.compare(value, F.fromU32(word)))

law exact_conversion_retains_duration:
  for value: F.F64
  for word: U32
  {T.checkedMilliseconds(value, word, Some{EQ{}}) == Done{word} : Result<&2, &2, T.MillisecondsError, U32>}

law smaller_conversion_is_rejected:
  for value: F.F64
  for word: U32
  {T.checkedMilliseconds(value, word, Some{LT{}}) == Fail{T.Unrepresentable{value}} : Result<&2, &2, T.MillisecondsError, U32>}

law larger_conversion_is_rejected:
  for value: F.F64
  for word: U32
  {T.checkedMilliseconds(value, word, Some{GT{}}) == Fail{T.Unrepresentable{value}} : Result<&2, &2, T.MillisecondsError, U32>}

law unordered_conversion_is_rejected:
  for value: F.F64
  for word: U32
  {T.checkedMilliseconds(value, word, None{}) == Fail{T.Unrepresentable{value}} : Result<&2, &2, T.MillisecondsError, U32>}

law accepted_durations_round_trip:
  for +value: F.F64
  {exactResult(value, T.millisecondsMilliseconds(value)) == True{} : Bool}
