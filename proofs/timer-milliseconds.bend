import Base
import ../laws/timer-milliseconds.bend as Laws
import ../packages/runtime/src/timer.bend as T
import ../packages/runtime/src/f64.bend as F

def Laws.exact_conversion_retains_duration(value, word): {==}
def Laws.smaller_conversion_is_rejected(value, word): {==}
def Laws.larger_conversion_is_rejected(value, word): {==}
def Laws.unordered_conversion_is_rejected(value, word): {==}

law checked_exact:
  for +value: F.F64
  for +word: U32
  for +comparison: Maybe<&2, Cmp>
  for equality: {F.compare(value, F.fromU32(word)) == comparison : Maybe<&2, Cmp>}
  {Laws.exactResult(value, T.checkedMilliseconds(value, word, comparison)) == True{} : Bool}

def checked_exact(value, word, comparison, equality):
  match comparison:
    case None{}: {==}
    case Some{LT{}}: {==}
    case Some{GT{}}: {==}
    case Some{EQ{}}: Equal.cong(Maybe<&2, Cmp>, Bool, Laws.equalComparison, F.compare(value, F.fromU32(word)), Some{EQ{}}, equality)


def Laws.accepted_durations_round_trip(value):
  +word = T.candidate(F.decode(value))
  checked_exact(value, word, F.compare(value, F.fromU32(word)), {==})
